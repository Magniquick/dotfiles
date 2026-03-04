// Package sysinfo reads Linux /proc and /sys metrics and returns JSON.
package sysinfo

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

// Output is the JSON-serialisable snapshot returned by Refresh.
type Output struct {
	CPU                float64 `json:"cpu"`
	Mem                int     `json:"mem"`
	MemUsed            string  `json:"mem_used"`
	MemTotal           string  `json:"mem_total"`
	Disk               int     `json:"disk"`
	DiskWorstCase      int     `json:"disk_worst_case"`
	DiskBtrfsAvailable bool    `json:"disk_btrfs_available"`
	DiskBtrfsFreeEst   float64 `json:"disk_btrfs_free_est_gib"`
	DiskBtrfsFreeMin   float64 `json:"disk_btrfs_free_min_gib"`
	DiskHealth         string  `json:"disk_health"`
	DiskWear           string  `json:"disk_wear"`
	DiskDevice         string  `json:"disk_device"`
	Temp               float64 `json:"temp"`
	Uptime             string  `json:"uptime"`
	PsiCPUSome         float64 `json:"psi_cpu_some"`
	PsiCPUFull         float64 `json:"psi_cpu_full"`
	PsiMemSome         float64 `json:"psi_mem_some"`
	PsiMemFull         float64 `json:"psi_mem_full"`
	PsiIOSome          float64 `json:"psi_io_some"`
	PsiIOFull          float64 `json:"psi_io_full"`
	Error              string  `json:"error,omitempty"`
}

// state persists across calls for CPU delta computation and disk-health caching.
var (
	mu               sync.Mutex
	lastCPUTotal     uint64
	lastCPUIdle      uint64
	lastDiskHealthAt time.Time
	diskHealthCache  string
	diskWearCache    string
	lastBtrfsAt      time.Time
	btrfsAvailable   bool
	btrfsFreeEst     float64
	btrfsFreeMin     float64
	btrfsWorstCase   int
)

// Refresh collects all metrics and returns a JSON string.
func Refresh(diskDevice string) string {
	mu.Lock()
	defer mu.Unlock()

	if diskDevice == "" {
		diskDevice = defaultDiskDevice()
	}

	out := Output{DiskDevice: diskDevice}
	var errs []string

	if err := updateCPU(&out); err != nil {
		errs = append(errs, err.Error())
	}
	if err := updateMemory(&out); err != nil {
		errs = append(errs, err.Error())
	}
	if err := updateDisk(&out); err != nil {
		errs = append(errs, err.Error())
	}
	updateBtrfs(&out)
	if err := updateTemp(&out); err != nil {
		errs = append(errs, err.Error())
	}
	if err := updateUptime(&out); err != nil {
		errs = append(errs, err.Error())
	}
	updatePSI(&out)
	updateDiskHealth(&out, diskDevice)

	if len(errs) > 0 {
		out.Error = strings.Join(errs, "; ")
	}

	b, _ := json.Marshal(out)
	return string(b)
}

func defaultDiskDevice() string {
	for _, c := range []string{"/dev/nvme0n1", "/dev/nvme0", "/dev/sda", "/dev/vda"} {
		if _, err := os.Stat(c); err == nil {
			return c
		}
	}
	return "/dev/nvme0n1"
}

// --- CPU ---

func updateCPU(out *Output) error {
	total, idle, err := readCPUTotals()
	if err != nil {
		return err
	}
	if lastCPUTotal != 0 && total > lastCPUTotal {
		dt := total - lastCPUTotal
		di := idle - lastCPUIdle
		if di > dt {
			di = dt
		}
		out.CPU = 100.0 * (1.0 - float64(di)/float64(dt))
	}
	lastCPUTotal = total
	lastCPUIdle = idle
	return nil
}

func readCPUTotals() (total, idle uint64, err error) {
	data, e := os.ReadFile("/proc/stat")
	if e != nil {
		return 0, 0, e
	}
	line := strings.SplitN(string(data), "\n", 2)[0]
	fields := strings.Fields(line)
	if len(fields) < 5 || fields[0] != "cpu" {
		return 0, 0, fmt.Errorf("malformed /proc/stat")
	}
	var vals [10]uint64
	for i := 1; i < len(fields) && i-1 < len(vals); i++ {
		fmt.Sscanf(fields[i], "%d", &vals[i-1])
		total += vals[i-1]
	}
	// idle = idle + iowait
	idle = vals[3] + vals[4]
	return total, idle, nil
}

// --- Memory ---

func updateMemory(out *Output) error {
	totalKB, availKB, err := readMeminfo()
	if err != nil {
		return err
	}
	if totalKB == 0 {
		return fmt.Errorf("MemTotal is zero")
	}
	usedKB := totalKB - availKB
	out.Mem = int(100.0 * float64(usedKB) / float64(totalKB))
	out.MemUsed = fmt.Sprintf("%.1fGB", float64(usedKB)/1024/1024)
	out.MemTotal = fmt.Sprintf("%.1fGB", float64(totalKB)/1024/1024)
	return nil
}

func readMeminfo() (totalKB, availKB uint64, err error) {
	data, e := os.ReadFile("/proc/meminfo")
	if e != nil {
		return 0, 0, e
	}
	for _, line := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(line, "MemTotal:") {
			fmt.Sscanf(strings.TrimPrefix(line, "MemTotal:"), "%d", &totalKB)
		} else if strings.HasPrefix(line, "MemAvailable:") {
			fmt.Sscanf(strings.TrimPrefix(line, "MemAvailable:"), "%d", &availKB)
		}
	}
	return
}

// --- Disk usage ---

func updateDisk(out *Output) error {
	var s syscall.Statfs_t
	if err := syscall.Statfs("/", &s); err != nil {
		return err
	}
	total := float64(s.Blocks) * float64(s.Bsize)
	avail := float64(s.Bavail) * float64(s.Bsize)
	used := total - avail
	if total > 0 {
		out.Disk = int(100.0 * used / total)
	}
	return nil
}

// --- Btrfs ---

func updateBtrfs(out *Output) {
	if !isBtrfsRoot() {
		out.DiskBtrfsAvailable = false
		out.DiskWorstCase = out.Disk
		return
	}

	now := time.Now()
	if now.Sub(lastBtrfsAt) > 30*time.Second {
		avail, est, min, worst := readBtrfsUsage()
		btrfsAvailable = avail
		btrfsFreeEst = est
		btrfsFreeMin = min
		btrfsWorstCase = worst
		lastBtrfsAt = now
	}

	out.DiskBtrfsAvailable = btrfsAvailable
	out.DiskBtrfsFreeEst = btrfsFreeEst
	out.DiskBtrfsFreeMin = btrfsFreeMin
	out.DiskWorstCase = btrfsWorstCase
}

func isBtrfsRoot() bool {
	data, err := os.ReadFile("/proc/self/mounts")
	if err != nil {
		return false
	}
	for _, line := range strings.Split(string(data), "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 3 && fields[1] == "/" {
			return fields[2] == "btrfs"
		}
	}
	return false
}

func readBtrfsUsage() (avail bool, freeEst, freeMin float64, worstCase int) {
	out, err := exec.Command("btrfs", "filesystem", "usage", "/").Output()
	if err != nil {
		return false, 0, 0, 0
	}
	text := string(out)
	est, min, ok := parseBtrfsFreeEstimated(text)
	if !ok {
		return false, 0, 0, 0
	}
	var s syscall.Statfs_t
	_ = syscall.Statfs("/", &s)
	totalGiB := float64(s.Blocks) * float64(s.Bsize) / 1024 / 1024 / 1024
	worst := 0
	if totalGiB > 0 {
		worst = int((1.0 - min/totalGiB) * 100)
		if worst < 0 {
			worst = 0
		}
		if worst > 100 {
			worst = 100
		}
	}
	return true, est, min, worst
}

func parseBtrfsFreeEstimated(text string) (est, min float64, ok bool) {
	for _, line := range strings.Split(text, "\n") {
		if !strings.Contains(line, "Free (estimated):") {
			continue
		}
		rest := strings.SplitN(line, "Free (estimated):", 2)[1]
		first := strings.Fields(rest)
		if len(first) == 0 {
			continue
		}
		est = parseSizeGiB(first[0])
		// min is in parentheses: "(min: 42.50GiB)"
		if idx := strings.Index(line, "(min:"); idx >= 0 {
			inner := line[idx+5:]
			if end := strings.Index(inner, ")"); end >= 0 {
				inner = strings.TrimSpace(inner[:end])
				min = parseSizeGiB(inner)
			}
		}
		return est, min, true
	}
	return 0, 0, false
}

func parseSizeGiB(s string) float64 {
	s = strings.ReplaceAll(s, ",", "")
	units := []struct {
		suffix string
		factor float64
	}{
		{"TiB", 1024},
		{"GiB", 1},
		{"MiB", 1.0 / 1024},
		{"KiB", 1.0 / (1024 * 1024)},
		{"B", 1.0 / (1024 * 1024 * 1024)},
	}
	for _, u := range units {
		if strings.HasSuffix(s, u.suffix) {
			num := strings.TrimSuffix(s, u.suffix)
			var v float64
			fmt.Sscanf(strings.TrimSpace(num), "%f", &v)
			return v * u.factor
		}
	}
	return 0
}

// --- Temperature ---

func updateTemp(out *Output) error {
	entries, err := filepath.Glob("/sys/class/thermal/thermal_zone*/temp")
	if err != nil || len(entries) == 0 {
		return nil
	}

	// Prefer CPU package temperature when available.
	for _, p := range entries {
		zoneDir := filepath.Dir(p)
		typeData, e := os.ReadFile(filepath.Join(zoneDir, "type"))
		if e != nil {
			continue
		}
		if strings.TrimSpace(string(typeData)) != "x86_pkg_temp" {
			continue
		}
		data, e := os.ReadFile(p)
		if e != nil {
			continue
		}
		var v float64
		if _, err2 := fmt.Sscanf(strings.TrimSpace(string(data)), "%f", &v); err2 == nil {
			out.Temp = v / 1000.0
			return nil
		}
	}

	// Fallback to the first readable thermal zone.
	for _, p := range entries {
		data, e := os.ReadFile(p)
		if e != nil {
			continue
		}
		var v float64
		if _, err2 := fmt.Sscanf(strings.TrimSpace(string(data)), "%f", &v); err2 == nil {
			out.Temp = v / 1000.0
			return nil
		}
	}

	return nil
}

// --- Uptime ---

func updateUptime(out *Output) error {
	data, err := os.ReadFile("/proc/uptime")
	if err != nil {
		return err
	}
	var secs float64
	fmt.Sscanf(strings.Fields(string(data))[0], "%f", &secs)
	out.Uptime = formatUptime(uint64(secs))
	return nil
}

func formatUptime(total uint64) string {
	days := total / 86400
	rem := total % 86400
	hours := rem / 3600
	rem %= 3600
	mins := rem / 60

	var parts []string
	if days > 0 {
		unit := "days"
		if days == 1 {
			unit = "day"
		}
		parts = append(parts, fmt.Sprintf("%d %s", days, unit))
	}
	if hours > 0 {
		unit := "hours"
		if hours == 1 {
			unit = "hour"
		}
		parts = append(parts, fmt.Sprintf("%d %s", hours, unit))
	}
	if mins > 0 || len(parts) == 0 {
		unit := "minutes"
		if mins == 1 {
			unit = "minute"
		}
		parts = append(parts, fmt.Sprintf("%d %s", mins, unit))
	}
	return strings.Join(parts, ", ")
}

// --- PSI ---

func updatePSI(out *Output) {
	out.PsiCPUSome, out.PsiCPUFull = readPSI("/proc/pressure/cpu")
	out.PsiMemSome, out.PsiMemFull = readPSI("/proc/pressure/memory")
	out.PsiIOSome, out.PsiIOFull = readPSI("/proc/pressure/io")
}

func readPSI(path string) (some, full float64) {
	data, err := os.ReadFile(path)
	if err != nil {
		return
	}
	for _, line := range strings.Split(string(data), "\n") {
		for _, field := range strings.Fields(line) {
			if strings.HasPrefix(field, "avg10=") {
				var v float64
				fmt.Sscanf(strings.TrimPrefix(field, "avg10="), "%f", &v)
				if strings.HasPrefix(line, "some") {
					some = v
				} else {
					full = v
				}
			}
		}
	}
	return
}

// --- Disk health ---

func updateDiskHealth(out *Output, device string) {
	now := time.Now()
	const ttl = 6 * time.Hour
	if diskHealthCache == "" || now.Sub(lastDiskHealthAt) > ttl {
		health, wear := readDiskHealth(device)
		diskHealthCache = health
		diskWearCache = wear
		lastDiskHealthAt = now
	}
	out.DiskHealth = diskHealthCache
	out.DiskWear = diskWearCache
}

func readDiskHealth(device string) (health, wear string) {
	attrs := runSmartctl("--attributes", device)
	healthOut := runSmartctl("--health", "--tolerance=conservative", device)

	if attrs == "" && healthOut == "" {
		return "Unknown (smartctl missing)", "Unknown"
	}

	critWarn := parseSmartctlValue(attrs, "Critical Warning:")
	if critWarn == "" {
		critWarn = "unknown"
	}
	wear = parseSmartctlValue(attrs, "Percentage Used:")
	if wear == "" {
		wear = "Unknown"
	}

	healthResult := "unknown"
	if v := parseSmartctlValue(healthOut, "result"); v != "" {
		healthResult = v
	} else if v := parseSmartctlValue(healthOut, "SMART Health Status:"); v != "" {
		healthResult = v
	}

	healthNorm := normalizeSmartToken(healthResult)
	critWarnNorm := normalizeSmartToken(critWarn)

	if healthNorm == "PASSED" && isZeroCriticalWarning(critWarnNorm) {
		health = "Healthy"
	} else if healthResult != "unknown" {
		health = fmt.Sprintf("%s (%s)", healthResult, critWarn)
	} else {
		health = fmt.Sprintf("Unknown (%s)", critWarn)
	}
	return
}

func runSmartctl(args ...string) string {
	out, err := exec.Command("smartctl", args...).Output()
	if err == nil {
		return string(out)
	}
	out, err = exec.Command("sudo", append([]string{"-n", "smartctl"}, args...)...).Output()
	if err == nil {
		return string(out)
	}
	return ""
}

func parseSmartctlValue(output, needle string) string {
	for _, line := range strings.Split(output, "\n") {
		if strings.Contains(line, needle) {
			parts := strings.SplitN(line, needle, 2)
			if len(parts) == 2 {
				return strings.Trim(strings.TrimSpace(parts[1]), ":")
			}
		}
	}
	return ""
}

func normalizeSmartToken(value string) string {
	t := strings.TrimSpace(value)
	if t == "" {
		return ""
	}

	// Keep the first token only (drop decorations like "(0x00)" or trailing comments).
	fields := strings.Fields(t)
	if len(fields) > 0 {
		t = fields[0]
	}

	// Also trim punctuation wrappers that show up on some smartctl variants.
	t = strings.Trim(t, "():")
	return strings.ToUpper(t)
}

func isZeroCriticalWarning(value string) bool {
	v := strings.ToUpper(strings.TrimSpace(value))
	if v == "" {
		return false
	}

	if strings.HasPrefix(v, "0X") {
		v = v[2:]
	}
	v = strings.TrimLeft(v, "0")
	return v == ""
}
