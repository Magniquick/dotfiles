package hyprland

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

type Snapshot struct {
	ActiveWorkspace json.RawMessage `json:"activeWorkspace"`
	Clients         json.RawMessage `json:"clients"`
	Error           string          `json:"error,omitempty"`
}

type MonitorCallback func()

var (
	monitorNext int32
	monitors    sync.Map // int32 -> chan struct{}
)

var relevantEvents = map[string]struct{}{
	"openwindow":         {},
	"closewindow":        {},
	"movewindow":         {},
	"movewindowv2":       {},
	"windowtitle":        {},
	"windowtitlev2":      {},
	"workspace":          {},
	"workspacev2":        {},
	"focusedmon":         {},
	"focusedmonv2":       {},
	"changefloatingmode": {},
	"fullscreen":         {},
	"pin":                {},
}

func Refresh() string {
	activeWorkspace, err := request("j/activeworkspace")
	if err != nil {
		return marshalSnapshot(Snapshot{Error: err.Error()})
	}

	clients, err := request("j/clients")
	if err != nil {
		return marshalSnapshot(Snapshot{
			ActiveWorkspace: activeWorkspace,
			Error:           err.Error(),
		})
	}

	return marshalSnapshot(Snapshot{
		ActiveWorkspace: activeWorkspace,
		Clients:         clients,
	})
}

func Monitor(cb MonitorCallback) int {
	id := int(atomic.AddInt32(&monitorNext, 1))
	stop := make(chan struct{}, 1)
	monitors.Store(id, stop)
	go runMonitor(id, stop, cb)
	return id
}

func StopMonitor(id int) {
	if value, ok := monitors.LoadAndDelete(id); ok {
		stop := value.(chan struct{})
		select {
		case stop <- struct{}{}:
		default:
		}
	}
}

func marshalSnapshot(snapshot Snapshot) string {
	data, err := json.Marshal(snapshot)
	if err != nil {
		fallback, _ := json.Marshal(Snapshot{Error: err.Error()})
		return string(fallback)
	}
	return string(data)
}

func socketBase() (string, error) {
	signature := strings.TrimSpace(os.Getenv("HYPRLAND_INSTANCE_SIGNATURE"))
	if signature == "" {
		return "", fmt.Errorf("HYPRLAND_INSTANCE_SIGNATURE is not set")
	}

	runtimeDir := strings.TrimSpace(os.Getenv("XDG_RUNTIME_DIR"))
	if runtimeDir == "" {
		runtimeDir = fmt.Sprintf("/run/user/%d", os.Getuid())
	}

	return filepath.Join(runtimeDir, "hypr", signature), nil
}

func request(command string) (json.RawMessage, error) {
	base, err := socketBase()
	if err != nil {
		return nil, err
	}

	conn, err := net.DialTimeout("unix", filepath.Join(base, ".socket.sock"), 2*time.Second)
	if err != nil {
		return nil, err
	}
	defer conn.Close()

	_ = conn.SetDeadline(time.Now().Add(2 * time.Second))
	if _, err := io.WriteString(conn, command); err != nil {
		return nil, err
	}

	payload, err := io.ReadAll(conn)
	if err != nil {
		return nil, err
	}

	payload = bytesTrimSpace(payload)
	if len(payload) == 0 {
		return nil, fmt.Errorf("empty response for %s", command)
	}
	if !json.Valid(payload) {
		return nil, fmt.Errorf("invalid JSON response for %s", command)
	}

	return json.RawMessage(payload), nil
}

func runMonitor(id int, stop chan struct{}, cb MonitorCallback) {
	defer monitors.Delete(id)

	backoff := 200 * time.Millisecond
	for {
		select {
		case <-stop:
			return
		default:
		}

		err := consumeEvents(stop, cb)
		if err == nil {
			return
		}

		if !sleepOrStop(stop, backoff) {
			return
		}
		if backoff < 2*time.Second {
			backoff *= 2
		}
	}
}

func consumeEvents(stop chan struct{}, cb MonitorCallback) error {
	base, err := socketBase()
	if err != nil {
		return err
	}

	conn, err := net.DialTimeout("unix", filepath.Join(base, ".socket2.sock"), 2*time.Second)
	if err != nil {
		return err
	}
	defer conn.Close()

	reader := bufio.NewReader(conn)
	for {
		select {
		case <-stop:
			return nil
		default:
		}

		line, err := reader.ReadString('\n')
		if err != nil {
			return err
		}

		name := parseEventName(line)
		if _, ok := relevantEvents[name]; ok && cb != nil {
			cb()
		}
	}
}

func parseEventName(line string) string {
	trimmed := strings.TrimSpace(line)
	if trimmed == "" {
		return ""
	}
	if index := strings.Index(trimmed, ">>"); index >= 0 {
		return trimmed[:index]
	}
	return trimmed
}

func sleepOrStop(stop chan struct{}, duration time.Duration) bool {
	timer := time.NewTimer(duration)
	defer timer.Stop()

	select {
	case <-stop:
		return false
	case <-timer.C:
		return true
	}
}

func bytesTrimSpace(data []byte) []byte {
	start := 0
	end := len(data)
	for start < end {
		switch data[start] {
		case ' ', '\n', '\r', '\t':
			start++
		default:
			goto trimEnd
		}
	}

trimEnd:
	for end > start {
		switch data[end-1] {
		case ' ', '\n', '\r', '\t':
			end--
		default:
			return data[start:end]
		}
	}

	return data[start:end]
}
