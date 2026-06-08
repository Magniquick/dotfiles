package sysstats

import (
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReadSnapshotUsesProcfsData(t *testing.T) {
	proc := makeProcFixture(t, map[string]string{
		"stat": `cpu 100 20 30 400 50 0 0 0 0 0
btime 1710000000
`,
		"meminfo": `MemTotal:       8388608 kB
MemAvailable:   2097152 kB
`,
		"pressure/cpu": `some avg10=1.50 avg60=0.20 avg300=0.10 total=10
full avg10=0.25 avg60=0.10 avg300=0.05 total=5
`,
		"pressure/memory": `some avg10=2.50 avg60=0.20 avg300=0.10 total=10
full avg10=0.50 avg60=0.10 avg300=0.05 total=5
`,
		"pressure/io": `some avg10=3.50 avg60=0.20 avg300=0.10 total=10
full avg10=0.75 avg60=0.10 avg300=0.05 total=5
`,
		"uptime":         "12345.67 890.12\n",
		"self/mountinfo": "36 25 0:32 / / rw,relatime shared:1 - btrfs /dev/nvme0n1p2 rw,ssd\n",
	})

	snap := ReadSnapshot(proc)

	assertNear(t, snap.CPUTotal, 6.0)
	assertNear(t, snap.CPUIdle, 4.5)
	if snap.MemTotalKiB != 8388608 || snap.MemAvailableKiB != 2097152 {
		t.Fatalf("memory = total %d available %d", snap.MemTotalKiB, snap.MemAvailableKiB)
	}
	assertNear(t, snap.PSICpuSome, 1.50)
	assertNear(t, snap.PSICpuFull, 0.25)
	assertNear(t, snap.PSIMemSome, 2.50)
	assertNear(t, snap.PSIMemFull, 0.50)
	assertNear(t, snap.PSIIOSome, 3.50)
	assertNear(t, snap.PSIIOFull, 0.75)
	if snap.UptimeSeconds != 12345 {
		t.Fatalf("uptime = %d, want 12345", snap.UptimeSeconds)
	}
	if snap.RootFSType != "btrfs" {
		t.Fatalf("root fs type = %q, want btrfs", snap.RootFSType)
	}
	if len(snap.Errors) != 0 {
		t.Fatalf("unexpected errors: %v", snap.Errors)
	}
}

func TestReadNetDevReturnsSelectedInterfaceCounters(t *testing.T) {
	proc := makeProcFixture(t, map[string]string{
		"net/dev": `Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 10 1 0 0 0 0 0 0 20 2 0 0 0 0 0 0
enp0s20f0u2i1: 123456 7 0 0 0 0 0 0 654321 8 0 0 0 0 0 0
`,
	})

	snap := ReadNetDev(proc, "enp0s20f0u2i1")

	if snap.Error != "" {
		t.Fatalf("unexpected error: %s", snap.Error)
	}
	if snap.RxBytes != 123456 || snap.TxBytes != 654321 {
		t.Fatalf("netdev = rx %d tx %d", snap.RxBytes, snap.TxBytes)
	}
}

func TestReadNetDevReportsMissingInterface(t *testing.T) {
	proc := makeProcFixture(t, map[string]string{
		"net/dev": `Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
lo: 10 1 0 0 0 0 0 0 20 2 0 0 0 0 0 0
`,
	})

	snap := ReadNetDev(proc, "wlan0")

	if !strings.Contains(snap.Error, "interface wlan0 not found") {
		t.Fatalf("error = %q, want missing interface", snap.Error)
	}
}

func makeProcFixture(t *testing.T, files map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	for name, body := range files {
		path := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatalf("mkdir fixture: %v", err)
		}
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatalf("write fixture %s: %v", name, err)
		}
	}
	return dir
}

func assertNear(t *testing.T, got, want float64) {
	t.Helper()
	if math.Abs(got-want) > 0.0001 {
		t.Fatalf("value = %f, want %f", got, want)
	}
}
