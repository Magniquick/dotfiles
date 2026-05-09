package mcp

import (
	"testing"

	"qs-go/internal/secrets"
)

func TestWithHostedTodoistAddsStreamableServerFromSecretServiceToken(t *testing.T) {
	cfgs := withHostedTodoist(nil, secrets.NewMapResolver(map[string]string{
		"TODOIST_API_TOKEN": "todoist-secret",
	}))

	if len(cfgs) != 1 {
		t.Fatalf("expected one hosted Todoist server, got %#v", cfgs)
	}
	cfg := cfgs[0]
	if cfg.ID != "todoist" || cfg.URL != hostedTodoistMCPURL || cfg.BearerToken != "todoist-secret" || !cfg.Enabled || !cfg.AutoConnect {
		t.Fatalf("unexpected hosted Todoist config: %#v", cfg)
	}
}

func TestWithHostedTodoistDoesNotDuplicateExplicitHostedServer(t *testing.T) {
	explicit := []ServerConfig{{
		ID:          "todoist-custom",
		Label:       "Todoist Custom",
		URL:         hostedTodoistMCPURL,
		Enabled:     true,
		AutoConnect: true,
		BearerToken: "explicit-token",
	}}

	cfgs := withHostedTodoist(explicit, secrets.NewMapResolver(map[string]string{
		"TODOIST_API_TOKEN": "secret-service-token",
	}))

	if len(cfgs) != 1 {
		t.Fatalf("expected explicit hosted server only, got %#v", cfgs)
	}
	if cfgs[0].ID != "todoist-custom" || cfgs[0].BearerToken != "explicit-token" {
		t.Fatalf("explicit hosted server should win: %#v", cfgs[0])
	}
}
