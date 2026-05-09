//go:build livetodoist

package mcp

import (
	"encoding/json"
	"testing"

	"qs-go/internal/secrets"
)

func TestLiveTodoistHostedMCPBearerToken(t *testing.T) {
	cleanup := secrets.UseResolverForTest(secrets.NewKeyringResolver(secrets.DefaultService))
	defer cleanup()

	token, ok := secrets.NewResolver().Lookup("TODOIST_API_TOKEN")
	if !ok || token == "" {
		t.Skip("TODOIST_API_TOKEN is not available in Secret Service")
	}

	config, err := json.Marshal([]ServerConfig{{
		ID:          "todoist-hosted",
		Label:       "Todoist Hosted",
		URL:         "https://ai.todoist.net/mcp",
		Enabled:     true,
		AutoConnect: true,
		BearerToken: token,
	}})
	if err != nil {
		t.Fatalf("marshal config: %v", err)
	}

	var snapshot Snapshot
	if err := json.Unmarshal([]byte(Refresh(string(config))), &snapshot); err != nil {
		t.Fatalf("decode snapshot: %v", err)
	}
	if snapshot.Error != "" {
		t.Fatalf("refresh error: %s", snapshot.Error)
	}

	var todoist ServerSnapshot
	for _, server := range snapshot.Servers {
		if server.ID == "todoist-hosted" {
			todoist = server
			break
		}
	}
	if !todoist.Connected {
		t.Fatalf("todoist hosted MCP not connected: %#v", todoist)
	}
	if todoist.ServerName != "todoist-mcp-server" {
		t.Fatalf("unexpected server name: %q", todoist.ServerName)
	}
	if todoist.ToolCount == 0 {
		t.Fatalf("expected hosted Todoist MCP tools")
	}
	t.Logf("connected server=%s version=%s tools=%d", todoist.ServerName, todoist.ServerVersion, todoist.ToolCount)
}
