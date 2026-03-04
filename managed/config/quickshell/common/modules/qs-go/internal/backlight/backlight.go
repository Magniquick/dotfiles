// Package backlight provides sysfs backlight control and udev-based change monitoring.
package backlight

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"

	netlink "github.com/pilebones/go-udev/netlink"
)

// Info is the JSON payload returned by Get.
type Info struct {
	Percent int    `json:"percent"`
	Device  string `json:"device"`
	Error   string `json:"error,omitempty"`
}

// --- Backlight discovery ---

func findBacklightDevice() (string, error) {
	base := "/sys/class/backlight"
	entries, err := os.ReadDir(base)
	if err != nil {
		return "", fmt.Errorf("no backlight devices: %w", err)
	}
	for _, e := range entries {
		return filepath.Join(base, e.Name()), nil
	}
	return "", fmt.Errorf("no backlight devices found in %s", base)
}

func readBrightness(devicePath string) (current, max int, err error) {
	read := func(name string) (int, error) {
		b, e := os.ReadFile(filepath.Join(devicePath, name))
		if e != nil {
			return 0, e
		}
		return strconv.Atoi(strings.TrimSpace(string(b)))
	}
	current, err = read("brightness")
	if err != nil {
		return
	}
	max, err = read("max_brightness")
	return
}

func brightnessPercent(devicePath string) (int, error) {
	cur, max, err := readBrightness(devicePath)
	if err != nil {
		return 0, err
	}
	if max == 0 {
		return 0, fmt.Errorf("max_brightness is 0")
	}
	pct := int(math.Round(float64(cur) / float64(max) * 100))
	if pct < 0 {
		pct = 0
	}
	if pct > 100 {
		pct = 100
	}
	return pct, nil
}

// Get returns a JSON string with current brightness.
func Get() string {
	dev, err := findBacklightDevice()
	if err != nil {
		b, _ := json.Marshal(Info{Error: err.Error()})
		return string(b)
	}
	pct, err := brightnessPercent(dev)
	if err != nil {
		b, _ := json.Marshal(Info{Device: filepath.Base(dev), Error: err.Error()})
		return string(b)
	}
	name := filepath.Base(dev)
	b, _ := json.Marshal(Info{Percent: pct, Device: name})
	return string(b)
}

// Set writes a brightness percentage [0-100] to sysfs.
func Set(percent int) string {
	if percent < 0 {
		percent = 0
	}
	if percent > 100 {
		percent = 100
	}

	dev, err := findBacklightDevice()
	if err != nil {
		b, _ := json.Marshal(Info{Error: err.Error()})
		return string(b)
	}

	_, max, err := readBrightness(dev)
	if err != nil {
		b, _ := json.Marshal(Info{Device: filepath.Base(dev), Error: err.Error()})
		return string(b)
	}

	target := int(math.Round(float64(percent) / 100.0 * float64(max)))
	if target < 1 && percent > 0 {
		target = 1
	}
	if target > max {
		target = max
	}

	err = os.WriteFile(filepath.Join(dev, "brightness"), []byte(strconv.Itoa(target)), 0644)
	if err != nil {
		b, _ := json.Marshal(Info{Device: filepath.Base(dev), Error: err.Error()})
		return string(b)
	}

	name := filepath.Base(dev)
	b, _ := json.Marshal(Info{Percent: percent, Device: name})
	return string(b)
}

// --- Monitor ---

// MonitorCallback is called from a goroutine whenever brightness changes.
type MonitorCallback func(percent int, device string)

var (
	monitorMu   sync.Mutex
	monitorNext int32
	monitors    sync.Map // int32 → chan struct{}
)

// Monitor starts a udev netlink monitor for backlight events.
// Returns a session ID that can be passed to StopMonitor.
func Monitor(cb MonitorCallback) int {
	id := int(atomic.AddInt32(&monitorNext, 1))
	stop := make(chan struct{})
	monitors.Store(id, stop)

	go runMonitor(id, stop, cb)
	return id
}

// StopMonitor terminates a monitor session.
func StopMonitor(id int) {
	if v, ok := monitors.LoadAndDelete(id); ok {
		ch := v.(chan struct{})
		select {
		case ch <- struct{}{}:
		default:
		}
	}
}

func runMonitor(id int, stop chan struct{}, cb MonitorCallback) {
	defer monitors.Delete(id)

	conn := new(netlink.UEventConn)
	// Try udev events first, fall back to kernel events.
	if err := conn.Connect(netlink.UdevEvent); err != nil {
		if err2 := conn.Connect(netlink.KernelEvent); err2 != nil {
			return
		}
	}
	defer conn.Close()

	queue := make(chan netlink.UEvent, 16)
	errors := make(chan error, 4)
	quit := conn.Monitor(queue, errors, nil) // filter manually

	defer func() {
		select {
		case quit <- struct{}{}:
		default:
		}
	}()

	for {
		select {
		case <-stop:
			return
		case event := <-queue:
			sub, _ := event.Env["SUBSYSTEM"]
			if sub != "backlight" {
				continue
			}
			// Re-read current brightness.
			dev, err := findBacklightDevice()
			if err != nil {
				continue
			}
			pct, err := brightnessPercent(dev)
			if err != nil {
				continue
			}
			cb(pct, filepath.Base(dev))
		case <-errors:
			// non-fatal; keep running
		}
	}
}
