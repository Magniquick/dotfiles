// Package appconfig reads non-secret leftpanel configuration.
package appconfig

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"

	"github.com/BurntSushi/toml"
)

// Config is the non-secret leftpanel configuration.
type Config struct {
	Model     ModelConfig               `toml:"model"`
	Providers map[string]ProviderConfig `toml:"providers"`
	Email     EmailConfig               `toml:"email"`
	Calendar  CalendarConfig            `toml:"calendar"`
}

// ModelConfig contains the default model selection.
type ModelConfig struct {
	Default string `toml:"default"`
}

// ProviderConfig contains provider connection overrides.
type ProviderConfig struct {
	BaseURL string `toml:"base_url"`
}

// EmailConfig lists configured email accounts.
type EmailConfig struct {
	Accounts []EmailAccountConfig `toml:"accounts"`
}

// EmailAccountConfig describes one non-secret email account.
type EmailAccountConfig struct {
	ID       string `toml:"id"`
	Provider string `toml:"provider"`
	Label    string `toml:"label"`
	Address  string `toml:"address"`
	From     string `toml:"from"`
	Username string `toml:"username"`
	IMAPHost string `toml:"imap_host"`
	IMAPPort int    `toml:"imap_port"`
	IMAPTLS  string `toml:"imap_tls"`
}

// CalendarConfig lists Google Calendar API sources.
type CalendarConfig struct {
	Accounts []CalendarAccountConfig `toml:"accounts"`
}

// CalendarAccountConfig maps a configured Google account to calendar ids.
type CalendarAccountConfig struct {
	Account     string   `toml:"account"`
	CalendarIDs []string `toml:"calendar_ids"`
}

var (
	configMu      sync.RWMutex
	configFactory = func() (Config, error) {
		return Load(DefaultPath())
	}
)

// Current returns the active config source.
func Current() (Config, error) {
	configMu.RLock()
	factory := configFactory
	configMu.RUnlock()
	return factory()
}

// UseConfigForTest replaces the config source for a test.
func UseConfigForTest(cfg Config) func() {
	cfg = normalize(cfg)
	configMu.Lock()
	previous := configFactory
	configFactory = func() (Config, error) { return cfg, nil }
	configMu.Unlock()
	return func() {
		configMu.Lock()
		configFactory = previous
		configMu.Unlock()
	}
}

// Default returns the built-in config defaults.
func Default() Config {
	return Config{
		Model: ModelConfig{Default: "local/gpt-5.4-mini"},
		Providers: map[string]ProviderConfig{
			"local": {BaseURL: "http://127.0.0.1:8317/v1"},
		},
	}
}

// Load reads config from path, returning defaults when the file is absent.
func Load(path string) (Config, error) {
	cfg := Default()
	path = strings.TrimSpace(path)
	if path == "" {
		return cfg, nil
	}
	if _, err := toml.DecodeFile(path, &cfg); err != nil {
		if os.IsNotExist(err) {
			return cfg, nil
		}
		return cfg, err
	}
	return normalize(cfg), nil
}

// DefaultPath discovers the leftpanel config path for the current shell checkout.
func DefaultPath() string {
	for _, key := range []string{"QS_SHELL_DIR", "QUICKSHELL_SHELL_DIR"} {
		if path := configPathInDir(os.Getenv(key)); path != "" {
			return path
		}
	}
	cwd, err := os.Getwd()
	if err != nil {
		return ""
	}
	for dir := cwd; dir != "" && dir != string(os.PathSeparator); dir = filepath.Dir(dir) {
		if path := configPathInDir(dir); path != "" {
			return path
		}
		next := filepath.Dir(dir)
		if next == dir {
			break
		}
	}
	return ""
}

func configPathInDir(dir string) string {
	dir = strings.TrimSpace(dir)
	if dir == "" {
		return ""
	}
	candidate := filepath.Join(dir, "leftpanel", "config.toml")
	//nolint:gosec // candidate is discovered by walking local shell config directories.
	if _, err := os.Stat(candidate); err == nil {
		return candidate
	}
	return ""
}

// PublicValues returns non-secret provider values as environment-style keys.
func (c Config) PublicValues() map[string]string {
	c = normalize(c)
	values := map[string]string{}
	if c.Model.Default != "" {
		values["OPENAI_MODEL"] = c.Model.Default
	}
	if provider, ok := c.Providers["openai"]; ok && strings.TrimSpace(provider.BaseURL) != "" {
		values["OPENAI_BASE_URL"] = strings.TrimSpace(provider.BaseURL)
	}
	if provider, ok := c.Providers["local"]; ok && strings.TrimSpace(provider.BaseURL) != "" {
		values["LOCAL_BASE_URL"] = strings.TrimSpace(provider.BaseURL)
	}
	return values
}

type lookupResolver interface {
	Lookup(key string) (string, bool)
}

// ResolveJSON returns public config and selected secrets as a JSON object.
func ResolveJSON(resolver lookupResolver) string {
	cfg, err := Current()
	if err != nil {
		cfg = Default()
	}
	values := cfg.PublicValues()
	if resolver != nil {
		for _, key := range []string{"OPENAI_API_KEY", "GEMINI_API_KEY", "LOCAL_API_KEY"} {
			if value, ok := resolver.Lookup(key); ok {
				values[key] = value
			}
		}
	}
	data, err := json.Marshal(values)
	if err != nil {
		return "{}"
	}
	return string(data)
}

// EmailEnv returns email account metadata as environment-style keys.
func (c Config) EmailEnv() map[string]string {
	values := map[string]string{}
	ids := make([]string, 0, len(c.Email.Accounts))
	for _, account := range c.Email.Accounts {
		id := strings.TrimSpace(account.ID)
		if id == "" {
			continue
		}
		ids = append(ids, id)
		prefix := "EMAIL_" + envID(id) + "_"
		add(values, prefix+"PROVIDER", account.Provider)
		add(values, prefix+"LABEL", account.Label)
		add(values, prefix+"ADDRESS", account.Address)
		add(values, prefix+"FROM", account.From)
		add(values, prefix+"USERNAME", account.Username)
		add(values, prefix+"IMAP_HOST", account.IMAPHost)
		if account.IMAPPort > 0 {
			values[prefix+"IMAP_PORT"] = strconv.Itoa(account.IMAPPort)
		}
		add(values, prefix+"IMAP_TLS", account.IMAPTLS)
	}
	if len(ids) > 0 {
		values["EMAIL_ACCOUNTS"] = strings.Join(ids, ",")
	}
	return values
}

func normalize(cfg Config) Config {
	if cfg.Model.Default = strings.TrimSpace(cfg.Model.Default); cfg.Model.Default == "" {
		cfg.Model.Default = "local/gpt-5.4-mini"
	}
	if cfg.Providers == nil {
		cfg.Providers = map[string]ProviderConfig{}
	}
	local := cfg.Providers["local"]
	if strings.TrimSpace(local.BaseURL) == "" {
		local.BaseURL = "http://127.0.0.1:8317/v1"
	}
	cfg.Providers["local"] = local
	for key, provider := range cfg.Providers {
		provider.BaseURL = strings.TrimSpace(provider.BaseURL)
		cfg.Providers[key] = provider
	}
	for i, source := range cfg.Calendar.Accounts {
		source.Account = strings.TrimSpace(source.Account)
		ids := make([]string, 0, len(source.CalendarIDs))
		for _, id := range source.CalendarIDs {
			if id = strings.TrimSpace(id); id != "" {
				ids = append(ids, id)
			}
		}
		source.CalendarIDs = ids
		cfg.Calendar.Accounts[i] = source
	}
	return cfg
}

func add(values map[string]string, key, value string) {
	if value = strings.TrimSpace(value); value != "" {
		values[key] = value
	}
}

func envID(id string) string {
	id = strings.ToUpper(strings.TrimSpace(id))
	replacer := strings.NewReplacer("-", "_", ".", "_", " ", "_")
	return replacer.Replace(id)
}
