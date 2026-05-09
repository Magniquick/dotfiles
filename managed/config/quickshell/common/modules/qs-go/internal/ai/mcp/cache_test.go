package mcp

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"qs-go/internal/ai/shared"
)

func TestToolDescriptorsDoesNotBlockOnColdRemoteCatalog(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		time.Sleep(500 * time.Millisecond)
		http.Error(w, "slow unavailable", http.StatusServiceUnavailable)
	}))
	t.Cleanup(srv.Close)

	config := mustConfigJSON(t, []ServerConfig{{
		ID:      "slow",
		Label:   "Slow MCP",
		URL:     srv.URL + "/mcp",
		Enabled: true,
	}})

	start := time.Now()
	tools, err := ToolDescriptors(config)
	elapsed := time.Since(start)
	if err != nil {
		t.Fatalf("ToolDescriptors should keep first-token path usable without a remote catalog: %v", err)
	}
	if elapsed > 200*time.Millisecond {
		t.Fatalf("ToolDescriptors blocked on remote MCP catalog for %s", elapsed)
	}

	names := map[string]bool{}
	for _, tool := range tools {
		names[tool.Name] = true
	}
	if !names["shell_command"] || !names["apply_patch"] {
		t.Fatalf("expected local tools to remain available, got %#v", names)
	}
}

func TestWithStreamHandlersDoesNotConnectBeforeStream(t *testing.T) {
	var requests atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		requests.Add(1)
		time.Sleep(500 * time.Millisecond)
		http.Error(w, "slow unavailable", http.StatusServiceUnavailable)
	}))
	t.Cleanup(srv.Close)

	config := mustConfigJSON(t, []ServerConfig{{
		ID:      "slow",
		Label:   "Slow MCP",
		URL:     srv.URL + "/mcp",
		Enabled: true,
	}})

	called := false
	start := time.Now()
	err := WithStreamHandlers(config, nil, nil, func() error {
		called = true
		return nil
	})
	elapsed := time.Since(start)
	if err != nil {
		t.Fatalf("WithStreamHandlers should not fail before the stream starts: %v", err)
	}
	if !called {
		t.Fatalf("stream callback was not called")
	}
	if elapsed > 200*time.Millisecond {
		t.Fatalf("WithStreamHandlers blocked on remote MCP connect for %s", elapsed)
	}
	if got := requests.Load(); got != 0 {
		t.Fatalf("WithStreamHandlers should not connect to MCP before a tool call, got %d request(s)", got)
	}
}

func TestToolDescriptorsUsesCachedRemoteCatalogUntilHardExpiry(t *testing.T) {
	t.Cleanup(useSnapshotCacheRootForTest(t.TempDir()))
	resetDefaultRuntimeForTest()
	t.Cleanup(resetDefaultRuntimeForTest)

	cfg := ServerConfig{
		ID:      "cached",
		Label:   "Cached MCP",
		URL:     "http://127.0.0.1:1/mcp",
		Enabled: true,
	}
	hash := configHash(cfg)
	conn := &serverConn{
		cfg:  cfg,
		hash: hash,
		snapshot: ServerSnapshot{
			ID:        cfg.ID,
			Label:     cfg.Label,
			URL:       cfg.URL,
			Enabled:   true,
			Connected: true,
			Status:    "connected",
			ToolCount: 1,
		},
		tools: []ToolSnapshot{{
			ServerID:      cfg.ID,
			ServerLabel:   cfg.Label,
			Name:          "cached_tool",
			QualifiedName: "cached__cached_tool",
			Description:   "Cached tool.",
			ReadOnly:      true,
		}},
	}
	if err := saveCachedServerSnapshot(cfg, hash, conn, time.Now().Add(-23*time.Hour)); err != nil {
		t.Fatalf("save fresh-enough cache: %v", err)
	}

	tools, err := ToolDescriptors(mustConfigJSON(t, []ServerConfig{cfg}))
	if err != nil {
		t.Fatalf("ToolDescriptors with cache: %v", err)
	}
	if !hasToolNamed(tools, "cached__cached_tool") {
		t.Fatalf("expected cached remote tool before hard expiry, got %#v", tools)
	}

	if err := saveCachedServerSnapshot(cfg, hash, conn, time.Now().Add(-25*time.Hour)); err != nil {
		t.Fatalf("save expired cache: %v", err)
	}
	resetDefaultRuntimeForTest()
	tools, err = ToolDescriptors(mustConfigJSON(t, []ServerConfig{cfg}))
	if err != nil {
		t.Fatalf("ToolDescriptors with expired cache should keep local tools usable: %v", err)
	}
	if hasToolNamed(tools, "cached__cached_tool") {
		t.Fatalf("expired remote catalog must not be exposed after 24h, got %#v", tools)
	}
}

func resetDefaultRuntimeForTest() {
	defaultRuntime = &runtime{
		configs:    map[string]ServerConfig{},
		conns:      map[string]*serverConn{},
		refreshing: map[string]bool{},
	}
}

func hasToolNamed(tools []shared.ToolDescriptor, name string) bool {
	for _, tool := range tools {
		if strings.TrimSpace(tool.Name) == name {
			return true
		}
	}
	return false
}

func mustConfigJSON(t *testing.T, cfgs []ServerConfig) string {
	t.Helper()
	//nolint:gosec // bearer_token is a fake test fixture value.
	raw, err := json.Marshal(cfgs)
	if err != nil {
		t.Fatalf("marshal config: %v", err)
	}
	return string(raw)
}
