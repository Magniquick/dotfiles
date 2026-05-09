package appconfig

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadTOMLReturnsPublicValuesAndEmailMetadata(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	if err := os.WriteFile(path, []byte(`
[model]
default = "gemini/gemini-2.5-flash"

[providers.local]
base_url = "http://127.0.0.1:8317/v1"

[providers.openai]
base_url = "https://api.example/v1"

[[email.accounts]]
id = "iit"
provider = "gmail"
label = "IIT Mail"
address = "me@example.edu"
username = "me@example.edu"
`), 0o600); err != nil {
		t.Fatal(err)
	}

	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("unexpected load error: %v", err)
	}
	public := cfg.PublicValues()
	if public["OPENAI_MODEL"] != "gemini/gemini-2.5-flash" {
		t.Fatalf("unexpected public values: %#v", public)
	}
	if public["OPENAI_BASE_URL"] != "https://api.example/v1" {
		t.Fatalf("missing openai base url: %#v", public)
	}

	email := cfg.EmailEnv()
	if email["EMAIL_ACCOUNTS"] != "iit" || email["EMAIL_IIT_ADDRESS"] != "me@example.edu" {
		t.Fatalf("unexpected email metadata: %#v", email)
	}
	if _, ok := email["EMAIL_IIT_IMAP_HOST"]; ok {
		t.Fatalf("gmail provider should not require explicit imap host metadata: %#v", email)
	}
	if _, ok := email["EMAIL_IIT_PASSWORD"]; ok {
		t.Fatalf("email metadata must not contain passwords: %#v", email)
	}
}

func TestDefaultKeepsLocalProvider(t *testing.T) {
	cfg, err := Load("")
	if err != nil {
		t.Fatalf("unexpected load error: %v", err)
	}
	public := cfg.PublicValues()
	if public["OPENAI_MODEL"] != "local/gpt-5.4-mini" {
		t.Fatalf("unexpected default model: %#v", public)
	}
	if public["LOCAL_BASE_URL"] != "http://127.0.0.1:8317/v1" {
		t.Fatalf("unexpected local base URL: %#v", public)
	}
}

func TestDefaultPathUsesShellDirEnvironment(t *testing.T) {
	shellDir := t.TempDir()
	leftpanelDir := filepath.Join(shellDir, "leftpanel")
	//nolint:gosec // test creates a normal temporary config directory.
	if err := os.MkdirAll(leftpanelDir, 0o755); err != nil {
		t.Fatal(err)
	}
	configPath := filepath.Join(leftpanelDir, "config.toml")
	if err := os.WriteFile(configPath, []byte("[model]\ndefault = \"local/gpt-5.4-mini\"\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	otherDir := t.TempDir()
	previousDir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(otherDir); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = os.Chdir(previousDir)
	})
	t.Setenv("QS_SHELL_DIR", shellDir)

	if got := DefaultPath(); got != configPath {
		t.Fatalf("DefaultPath() = %q, want %q", got, configPath)
	}
}

type testResolver map[string]string

func (r testResolver) Lookup(key string) (string, bool) {
	value, ok := r[key]
	return value, ok
}

func TestResolveJSONCombinesConfigWithSecretKeys(t *testing.T) {
	cleanup := UseConfigForTest(Config{
		Model: ModelConfig{Default: "local/gpt-5.4-mini"},
		Providers: map[string]ProviderConfig{
			"local":  {BaseURL: "http://127.0.0.1:8317/v1"},
			"openai": {BaseURL: "https://api.example/v1"},
		},
	})
	defer cleanup()

	raw := ResolveJSON(testResolver{
		"OPENAI_API_KEY":     "openai-secret",
		"GEMINI_API_KEY":     "gemini-secret",
		"TODOIST_API_TOKEN":  "todoist-secret",
		"CALENDAR_ICAL_URL":  "https://calendar.example/ics",
		"EMAIL_IIT_PASSWORD": "email-secret",
	})

	if !strings.Contains(raw, "openai-secret") || !strings.Contains(raw, "https://api.example/v1") {
		t.Fatalf("expected provider config and API secret in json: %s", raw)
	}
	for _, hidden := range []string{"todoist-secret", "calendar.example", "email-secret"} {
		if strings.Contains(raw, hidden) {
			t.Fatalf("json exposed non-provider secret %q in %s", hidden, raw)
		}
	}
}
