package sysstats

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/prometheus/procfs"
)

const defaultProcMount = "/proc"

type Snapshot struct {
	CPUTotal        float64  `json:"cpu_total"`
	CPUIdle         float64  `json:"cpu_idle"`
	MemTotalKiB     uint64   `json:"mem_total_kib"`
	MemAvailableKiB uint64   `json:"mem_available_kib"`
	PSICpuSome      float64  `json:"psi_cpu_some"`
	PSICpuFull      float64  `json:"psi_cpu_full"`
	PSIMemSome      float64  `json:"psi_mem_some"`
	PSIMemFull      float64  `json:"psi_mem_full"`
	PSIIOSome       float64  `json:"psi_io_some"`
	PSIIOFull       float64  `json:"psi_io_full"`
	UptimeSeconds   uint64   `json:"uptime_seconds"`
	RootFSType      string   `json:"root_fs_type"`
	Errors          []string `json:"errors,omitempty"`
}

type NetDevSnapshot struct {
	Name    string `json:"name"`
	RxBytes uint64 `json:"rx_bytes"`
	TxBytes uint64 `json:"tx_bytes"`
	Error   string `json:"error,omitempty"`
}

func SnapshotJSON() string {
	return mustJSON(ReadSnapshot(defaultProcMount))
}

func NetDevJSON(iface string) string {
	return mustJSON(ReadNetDev(defaultProcMount, iface))
}

func ReadSnapshot(procMount string) Snapshot {
	var snap Snapshot
	fs, err := procfs.NewFS(procMount)
	if err != nil {
		snap.Errors = append(snap.Errors, fmt.Sprintf("procfs: %v", err))
		return snap
	}

	stat, err := fs.Stat()
	if err != nil {
		snap.Errors = append(snap.Errors, fmt.Sprintf("stat: %v", err))
	} else {
		snap.CPUTotal = cpuTotal(stat.CPUTotal)
		snap.CPUIdle = stat.CPUTotal.Idle + stat.CPUTotal.Iowait
	}

	mem, err := fs.Meminfo()
	if err != nil {
		snap.Errors = append(snap.Errors, fmt.Sprintf("meminfo: %v", err))
	} else {
		if mem.MemTotal != nil {
			snap.MemTotalKiB = *mem.MemTotal
		}
		if mem.MemAvailable != nil {
			snap.MemAvailableKiB = *mem.MemAvailable
		}
		if snap.MemTotalKiB == 0 {
			snap.Errors = append(snap.Errors, "MemTotal is zero")
		}
	}

	snap.PSICpuSome, snap.PSICpuFull = readPSIAvg10(fs, "cpu", &snap.Errors)
	snap.PSIMemSome, snap.PSIMemFull = readPSIAvg10(fs, "memory", &snap.Errors)
	snap.PSIIOSome, snap.PSIIOFull = readPSIAvg10(fs, "io", &snap.Errors)

	secs, err := readUptimeSeconds(procMount)
	if err != nil {
		snap.Errors = append(snap.Errors, fmt.Sprintf("uptime: %v", err))
	} else {
		snap.UptimeSeconds = secs
	}

	mounts, err := fs.GetMounts()
	if err != nil {
		if !os.IsNotExist(err) {
			snap.Errors = append(snap.Errors, fmt.Sprintf("mountinfo: %v", err))
		}
	} else {
		for _, mount := range mounts {
			if mount != nil && mount.MountPoint == "/" {
				snap.RootFSType = mount.FSType
				break
			}
		}
	}

	return snap
}

func ReadNetDev(procMount, iface string) NetDevSnapshot {
	iface = strings.TrimSpace(iface)
	if iface == "" {
		return NetDevSnapshot{Error: "interface is empty"}
	}

	fs, err := procfs.NewFS(procMount)
	if err != nil {
		return NetDevSnapshot{Name: iface, Error: fmt.Sprintf("procfs: %v", err)}
	}
	devs, err := fs.NetDev()
	if err != nil {
		return NetDevSnapshot{Name: iface, Error: fmt.Sprintf("netdev: %v", err)}
	}
	dev, ok := devs[iface]
	if !ok {
		return NetDevSnapshot{Name: iface, Error: fmt.Sprintf("interface %s not found", iface)}
	}

	return NetDevSnapshot{
		Name:    dev.Name,
		RxBytes: dev.RxBytes,
		TxBytes: dev.TxBytes,
	}
}

func cpuTotal(cpu procfs.CPUStat) float64 {
	return cpu.User + cpu.Nice + cpu.System + cpu.Idle + cpu.Iowait +
		cpu.IRQ + cpu.SoftIRQ + cpu.Steal + cpu.Guest + cpu.GuestNice
}

func readPSIAvg10(fs procfs.FS, resource string, errors *[]string) (float64, float64) {
	psi, err := fs.PSIStatsForResource(resource)
	if err != nil {
		if !os.IsNotExist(err) {
			*errors = append(*errors, fmt.Sprintf("psi %s: %v", resource, err))
		}
		return 0, 0
	}

	var some, full float64
	if psi.Some != nil {
		some = psi.Some.Avg10
	}
	if psi.Full != nil {
		full = psi.Full.Avg10
	}
	return some, full
}

func readUptimeSeconds(procMount string) (uint64, error) {
	raw, err := os.ReadFile(filepath.Join(procMount, "uptime"))
	if err != nil {
		return 0, err
	}
	fields := strings.Fields(string(raw))
	if len(fields) == 0 {
		return 0, fmt.Errorf("empty uptime")
	}
	secs, err := strconv.ParseFloat(fields[0], 64)
	if err != nil {
		return 0, err
	}
	if secs < 0 || math.IsNaN(secs) || math.IsInf(secs, 0) {
		return 0, fmt.Errorf("invalid uptime %q", fields[0])
	}
	return uint64(secs), nil
}

func mustJSON(value any) string {
	raw, err := json.Marshal(value)
	if err != nil {
		return `{"error":"json marshal failed"}`
	}
	return string(raw)
}
