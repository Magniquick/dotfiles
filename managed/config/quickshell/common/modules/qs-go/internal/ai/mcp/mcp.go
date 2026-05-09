package mcp

import (
	"bytes"
	"context"
	"crypto/sha1"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"

	"qs-go/internal/ai/shared"
)

const clientVersion = "v1.0.0"

type ServerConfig struct {
	ID          string            `json:"id"`
	Label       string            `json:"label,omitempty"`
	URL         string            `json:"url"`
	Enabled     bool              `json:"enabled"`
	AutoConnect bool              `json:"auto_connect,omitempty"`
	BearerToken string            `json:"bearer_token,omitempty"`
	Headers     map[string]string `json:"headers,omitempty"`
}

type ServerSnapshot struct {
	ID            string         `json:"id"`
	Label         string         `json:"label"`
	URL           string         `json:"url"`
	Enabled       bool           `json:"enabled"`
	Connected     bool           `json:"connected"`
	Status        string         `json:"status"`
	Error         string         `json:"error,omitempty"`
	ServerName    string         `json:"server_name,omitempty"`
	ServerVersion string         `json:"server_version,omitempty"`
	Instructions  string         `json:"instructions,omitempty"`
	ToolCount     int            `json:"tool_count"`
	PromptCount   int            `json:"prompt_count"`
	ResourceCount int            `json:"resource_count"`
	Capabilities  map[string]any `json:"capabilities,omitempty"`
}

type ToolSnapshot struct {
	ServerID      string         `json:"server_id"`
	ServerLabel   string         `json:"server_label"`
	Name          string         `json:"name"`
	QualifiedName string         `json:"qualified_name"`
	Title         string         `json:"title,omitempty"`
	Description   string         `json:"description,omitempty"`
	InputSchema   map[string]any `json:"input_schema,omitempty"`
	OutputSchema  map[string]any `json:"output_schema,omitempty"`
}

type PromptSnapshot struct {
	ServerID    string      `json:"server_id"`
	ServerLabel string      `json:"server_label"`
	Name        string      `json:"name"`
	Title       string      `json:"title,omitempty"`
	Description string      `json:"description,omitempty"`
	Arguments   []PromptArg `json:"arguments,omitempty"`
}

type PromptArg struct {
	Name        string `json:"name"`
	Description string `json:"description,omitempty"`
	Required    bool   `json:"required"`
}

type ResourceSnapshot struct {
	ServerID    string `json:"server_id"`
	ServerLabel string `json:"server_label"`
	URI         string `json:"uri"`
	Name        string `json:"name"`
	Title       string `json:"title,omitempty"`
	Description string `json:"description,omitempty"`
	MIMEType    string `json:"mime_type,omitempty"`
}

type PromptResult struct {
	ServerID    string        `json:"server_id"`
	ServerLabel string        `json:"server_label"`
	Name        string        `json:"name"`
	Description string        `json:"description,omitempty"`
	Messages    []PromptEntry `json:"messages"`
}

type PromptEntry struct {
	Role string `json:"role"`
	Text string `json:"text"`
}

type ResourceReadResult struct {
	ServerID    string          `json:"server_id"`
	ServerLabel string          `json:"server_label"`
	Contents    []ResourceEntry `json:"contents"`
}

type ResourceEntry struct {
	URI      string `json:"uri"`
	MIMEType string `json:"mime_type,omitempty"`
	Text     string `json:"text,omitempty"`
	BlobB64  string `json:"blob_b64,omitempty"`
}

type Snapshot struct {
	Servers   []ServerSnapshot   `json:"servers"`
	Tools     []ToolSnapshot     `json:"tools"`
	Prompts   []PromptSnapshot   `json:"prompts"`
	Resources []ResourceSnapshot `json:"resources"`
	Status    string             `json:"status"`
	Error     string             `json:"error,omitempty"`
}

type SamplingHandler func(context.Context, *sdk.CreateMessageWithToolsRequest) (*sdk.CreateMessageWithToolsResult, error)
type ElicitationHandler func(context.Context, *sdk.ElicitRequest) (*sdk.ElicitResult, error)

type runtime struct {
	mu sync.Mutex

	configs map[string]ServerConfig
	conns   map[string]*serverConn

	sampling    SamplingHandler
	elicitation ElicitationHandler
}

type serverConn struct {
	cfg       ServerConfig
	hash      string
	client    *sdk.Client
	session   *sdk.ClientSession
	snapshot  ServerSnapshot
	tools     []ToolSnapshot
	prompts   []PromptSnapshot
	resources []ResourceSnapshot
}

var defaultRuntime = &runtime{
	configs: map[string]ServerConfig{},
	conns:   map[string]*serverConn{},
}

func Refresh(configJSON string) string {
	snapshot := defaultRuntime.refresh(parseConfig(configJSON))
	return mustJSON(snapshot)
}

func ToolDescriptors(configJSON string) ([]shared.ToolDescriptor, error) {
	snapshot := defaultRuntime.refresh(parseConfig(configJSON))
	out := make([]shared.ToolDescriptor, 0, len(snapshot.Tools))
	for _, tool := range snapshot.Tools {
		name := firstNonEmpty(tool.QualifiedName, qualifiedToolName(tool.ServerID, tool.Name))
		if strings.TrimSpace(tool.ServerID) == "builtin" {
			name = strings.TrimSpace(tool.Name)
		}
		out = append(out, shared.ToolDescriptor{
			Name:        name,
			Title:       tool.Title,
			Description: tool.Description,
			InputSchema: tool.InputSchema,
			Kind:        builtinToolKind(tool),
			Format:      builtinToolFormat(tool),
			ServerID:    tool.ServerID,
			ServerLabel: tool.ServerLabel,
		})
	}
	if len(out) == 0 && strings.TrimSpace(snapshot.Error) != "" {
		return nil, errors.New(snapshot.Error)
	}
	return out, nil
}

func builtinToolKind(tool ToolSnapshot) string {
	if tool.ServerID == "builtin" && tool.Name == "apply_patch" {
		return "freeform"
	}
	return ""
}

func builtinToolFormat(tool ToolSnapshot) map[string]any {
	if tool.ServerID == "builtin" && tool.Name == "apply_patch" {
		return map[string]any{
			"type":       "grammar",
			"syntax":     "lark",
			"definition": applyPatchLarkGrammar,
		}
	}
	return nil
}

func CallTool(configJSON string, serverID string, toolName string, arguments map[string]any) (shared.ToolResult, error) {
	serverID, toolName = splitQualifiedToolName(serverID, toolName)
	if strings.TrimSpace(serverID) == "builtin" || (strings.TrimSpace(serverID) == "" && isBuiltinTool(toolName)) {
		return callBuiltinTool(toolName, arguments), nil
	}

	cfgs := parseConfig(configJSON)
	if _, err := defaultRuntime.ensure(cfgs); err != nil {
		return shared.ToolResult{}, err
	}

	defaultRuntime.mu.Lock()
	conn, ok := defaultRuntime.conns[strings.TrimSpace(serverID)]
	defaultRuntime.mu.Unlock()
	if !ok || conn == nil || conn.session == nil {
		return shared.ToolResult{}, fmt.Errorf("MCP server '%s' is not connected", serverID)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	res, err := conn.session.CallTool(ctx, &sdk.CallToolParams{
		Name:      strings.TrimSpace(toolName),
		Arguments: normalizeArgs(arguments),
	})
	if err != nil {
		return shared.ToolResult{}, err
	}

	var data map[string]any
	if res.StructuredContent != nil {
		if mapped, ok := res.StructuredContent.(map[string]any); ok {
			data = mapped
		}
	}

	return shared.ToolResult{
		Name:    toolName,
		Text:    joinContent(res.Content),
		Data:    data,
		IsError: res.IsError,
	}, nil
}

func GetPrompt(configJSON string, serverID string, promptName string, argsJSON string) string {
	args := map[string]string{}
	if strings.TrimSpace(argsJSON) != "" {
		_ = json.Unmarshal([]byte(argsJSON), &args)
	}

	cfgs := parseConfig(configJSON)
	if _, err := defaultRuntime.ensure(cfgs); err != nil {
		return mustJSON(map[string]any{"error": err.Error()})
	}

	defaultRuntime.mu.Lock()
	conn := defaultRuntime.conns[strings.TrimSpace(serverID)]
	defaultRuntime.mu.Unlock()
	if conn == nil || conn.session == nil {
		return mustJSON(map[string]any{"error": fmt.Sprintf("MCP server '%s' is not connected", serverID)})
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	res, err := conn.session.GetPrompt(ctx, &sdk.GetPromptParams{
		Name:      strings.TrimSpace(promptName),
		Arguments: args,
	})
	if err != nil {
		return mustJSON(map[string]any{"error": err.Error()})
	}

	out := PromptResult{
		ServerID:    conn.cfg.ID,
		ServerLabel: serverLabel(conn.cfg),
		Name:        promptName,
		Description: strings.TrimSpace(res.Description),
		Messages:    make([]PromptEntry, 0, len(res.Messages)),
	}
	for _, msg := range res.Messages {
		out.Messages = append(out.Messages, PromptEntry{
			Role: string(msg.Role),
			Text: contentToText(msg.Content),
		})
	}
	return mustJSON(out)
}

func ReadResource(configJSON string, serverID string, uri string) string {
	cfgs := parseConfig(configJSON)
	if _, err := defaultRuntime.ensure(cfgs); err != nil {
		return mustJSON(map[string]any{"error": err.Error()})
	}

	defaultRuntime.mu.Lock()
	conn := defaultRuntime.conns[strings.TrimSpace(serverID)]
	defaultRuntime.mu.Unlock()
	if conn == nil || conn.session == nil {
		return mustJSON(map[string]any{"error": fmt.Sprintf("MCP server '%s' is not connected", serverID)})
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	res, err := conn.session.ReadResource(ctx, &sdk.ReadResourceParams{URI: strings.TrimSpace(uri)})
	if err != nil {
		return mustJSON(map[string]any{"error": err.Error()})
	}

	out := ResourceReadResult{
		ServerID:    conn.cfg.ID,
		ServerLabel: serverLabel(conn.cfg),
		Contents:    make([]ResourceEntry, 0, len(res.Contents)),
	}
	for _, item := range res.Contents {
		out.Contents = append(out.Contents, ResourceEntry{
			URI:      item.URI,
			MIMEType: item.MIMEType,
			Text:     item.Text,
			BlobB64:  base64.StdEncoding.EncodeToString(item.Blob),
		})
	}
	return mustJSON(out)
}

func WithStreamHandlers(configJSON string, sampling SamplingHandler, elicitation ElicitationHandler, fn func() error) error {
	if _, err := defaultRuntime.ensure(parseConfig(configJSON)); err != nil {
		return err
	}

	defaultRuntime.mu.Lock()
	prevSampling := defaultRuntime.sampling
	prevElicitation := defaultRuntime.elicitation
	defaultRuntime.sampling = sampling
	defaultRuntime.elicitation = elicitation
	defaultRuntime.mu.Unlock()

	defer func() {
		defaultRuntime.mu.Lock()
		defaultRuntime.sampling = prevSampling
		defaultRuntime.elicitation = prevElicitation
		defaultRuntime.mu.Unlock()
	}()

	return fn()
}

func (r *runtime) refresh(cfgs []ServerConfig) Snapshot {
	result, err := r.ensure(cfgs)
	if err != nil {
		result.Error = err.Error()
		if result.Status == "" {
			result.Status = "error"
		}
	}
	return result
}

func (r *runtime) ensure(cfgs []ServerConfig) (Snapshot, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	next := make(map[string]ServerConfig, len(cfgs))
	for _, cfg := range cfgs {
		id := strings.TrimSpace(cfg.ID)
		if id == "" {
			continue
		}
		next[id] = cfg
	}

	for id, conn := range r.conns {
		if _, ok := next[id]; ok {
			continue
		}
		if conn != nil && conn.session != nil {
			_ = conn.session.Close()
		}
		delete(r.conns, id)
	}
	r.configs = next

	var errs []string
	for _, cfg := range cfgs {
		if !cfg.Enabled {
			r.conns[cfg.ID] = &serverConn{
				cfg: cfg,
				snapshot: ServerSnapshot{
					ID:      cfg.ID,
					Label:   serverLabel(cfg),
					URL:     cfg.URL,
					Enabled: cfg.Enabled,
					Status:  "disabled",
				},
			}
			continue
		}
		hash := configHash(cfg)
		existing := r.conns[cfg.ID]
		if existing != nil && existing.hash == hash && existing.session != nil {
			continue
		}
		if existing != nil && existing.session != nil {
			_ = existing.session.Close()
		}
		conn, err := r.connectLocked(cfg, hash)
		r.conns[cfg.ID] = conn
		if err != nil {
			errs = append(errs, fmt.Sprintf("%s: %v", cfg.ID, err))
		}
	}

	snapshot := r.snapshotLocked()
	if len(errs) > 0 {
		return snapshot, errors.New(strings.Join(errs, "; "))
	}
	return snapshot, nil
}

func (r *runtime) connectLocked(cfg ServerConfig, hash string) (*serverConn, error) {
	conn := &serverConn{
		cfg:  cfg,
		hash: hash,
		snapshot: ServerSnapshot{
			ID:      cfg.ID,
			Label:   serverLabel(cfg),
			URL:     cfg.URL,
			Enabled: cfg.Enabled,
			Status:  "connecting",
		},
	}

	client := sdk.NewClient(&sdk.Implementation{Name: "qs-go-mcp-client", Version: clientVersion}, &sdk.ClientOptions{
		CreateMessageWithToolsHandler: func(ctx context.Context, req *sdk.CreateMessageWithToolsRequest) (*sdk.CreateMessageWithToolsResult, error) {
			return r.handleSampling(ctx, req)
		},
		ElicitationHandler: func(ctx context.Context, req *sdk.ElicitRequest) (*sdk.ElicitResult, error) {
			return r.handleElicitation(ctx, req)
		},
	})

	httpClient := &http.Client{
		Timeout: 60 * time.Second,
		Transport: &authRoundTripper{
			base:    http.DefaultTransport,
			headers: cfg.Headers,
			token:   cfg.BearerToken,
		},
	}
	session, err := client.Connect(context.Background(), &sdk.StreamableClientTransport{
		Endpoint:   strings.TrimSpace(cfg.URL),
		HTTPClient: httpClient,
	}, nil)
	if err != nil {
		conn.snapshot.Status = "error"
		conn.snapshot.Error = err.Error()
		return conn, err
	}

	conn.client = client
	conn.session = session
	conn.snapshot.Connected = true
	conn.snapshot.Status = "connected"
	r.populateLocked(conn)
	return conn, nil
}

func (r *runtime) populateLocked(conn *serverConn) {
	if conn == nil || conn.session == nil {
		return
	}
	init := conn.session.InitializeResult()
	if init != nil {
		if init.ServerInfo != nil {
			conn.snapshot.ServerName = init.ServerInfo.Name
			conn.snapshot.ServerVersion = init.ServerInfo.Version
		}
		conn.snapshot.Instructions = strings.TrimSpace(init.Instructions)
		if init.Capabilities != nil {
			conn.snapshot.Capabilities = map[string]any{
				"tools":     init.Capabilities.Tools != nil,
				"prompts":   init.Capabilities.Prompts != nil,
				"resources": init.Capabilities.Resources != nil,
				"logging":   init.Capabilities.Logging != nil,
			}
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if res, err := conn.session.ListTools(ctx, nil); err == nil {
		conn.tools = make([]ToolSnapshot, 0, len(res.Tools))
		for _, tool := range res.Tools {
			if tool == nil {
				continue
			}
			conn.tools = append(conn.tools, ToolSnapshot{
				ServerID:      conn.cfg.ID,
				ServerLabel:   serverLabel(conn.cfg),
				Name:          tool.Name,
				QualifiedName: qualifiedToolName(conn.cfg.ID, tool.Name),
				Title:         strings.TrimSpace(tool.Title),
				Description:   strings.TrimSpace(tool.Description),
				InputSchema:   asMap(tool.InputSchema),
				OutputSchema:  asMap(tool.OutputSchema),
			})
		}
		conn.snapshot.ToolCount = len(conn.tools)
	}

	if res, err := conn.session.ListPrompts(ctx, nil); err == nil {
		conn.prompts = make([]PromptSnapshot, 0, len(res.Prompts))
		for _, prompt := range res.Prompts {
			if prompt == nil {
				continue
			}
			item := PromptSnapshot{
				ServerID:    conn.cfg.ID,
				ServerLabel: serverLabel(conn.cfg),
				Name:        prompt.Name,
				Title:       strings.TrimSpace(prompt.Title),
				Description: strings.TrimSpace(prompt.Description),
				Arguments:   make([]PromptArg, 0, len(prompt.Arguments)),
			}
			for _, arg := range prompt.Arguments {
				if arg == nil {
					continue
				}
				item.Arguments = append(item.Arguments, PromptArg{
					Name:        arg.Name,
					Description: strings.TrimSpace(arg.Description),
					Required:    arg.Required,
				})
			}
			conn.prompts = append(conn.prompts, item)
		}
		conn.snapshot.PromptCount = len(conn.prompts)
	}

	if res, err := conn.session.ListResources(ctx, nil); err == nil {
		conn.resources = make([]ResourceSnapshot, 0, len(res.Resources))
		for _, resource := range res.Resources {
			if resource == nil {
				continue
			}
			conn.resources = append(conn.resources, ResourceSnapshot{
				ServerID:    conn.cfg.ID,
				ServerLabel: serverLabel(conn.cfg),
				URI:         resource.URI,
				Name:        resource.Name,
				Title:       strings.TrimSpace(resource.Title),
				Description: strings.TrimSpace(resource.Description),
				MIMEType:    strings.TrimSpace(resource.MIMEType),
			})
		}
		conn.snapshot.ResourceCount = len(conn.resources)
	}
}

func (r *runtime) snapshotLocked() Snapshot {
	out := Snapshot{
		Servers:   []ServerSnapshot{builtinServerSnapshot()},
		Tools:     []ToolSnapshot{},
		Prompts:   []PromptSnapshot{},
		Resources: []ResourceSnapshot{},
		Status:    "ready",
	}
	out.Tools = append(out.Tools, builtinToolSnapshots()...)
	for _, conn := range r.conns {
		if conn == nil {
			continue
		}
		out.Servers = append(out.Servers, conn.snapshot)
		out.Tools = append(out.Tools, conn.tools...)
		out.Prompts = append(out.Prompts, conn.prompts...)
		out.Resources = append(out.Resources, conn.resources...)
	}

	slices.SortFunc(out.Servers, func(a, b ServerSnapshot) int { return strings.Compare(a.Label+a.ID, b.Label+b.ID) })
	slices.SortFunc(out.Tools, func(a, b ToolSnapshot) int { return strings.Compare(a.ServerLabel+a.Name, b.ServerLabel+b.Name) })
	slices.SortFunc(out.Prompts, func(a, b PromptSnapshot) int { return strings.Compare(a.ServerLabel+a.Name, b.ServerLabel+b.Name) })
	slices.SortFunc(out.Resources, func(a, b ResourceSnapshot) int { return strings.Compare(a.ServerLabel+a.Name, b.ServerLabel+b.Name) })

	if len(out.Servers) == 0 {
		out.Status = "empty"
	}
	return out
}

func (r *runtime) handleSampling(ctx context.Context, req *sdk.CreateMessageWithToolsRequest) (*sdk.CreateMessageWithToolsResult, error) {
	r.mu.Lock()
	handler := r.sampling
	r.mu.Unlock()
	if handler == nil {
		return nil, fmt.Errorf("MCP sampling is not available outside an active chat stream")
	}
	return handler(ctx, req)
}

func (r *runtime) handleElicitation(ctx context.Context, req *sdk.ElicitRequest) (*sdk.ElicitResult, error) {
	r.mu.Lock()
	handler := r.elicitation
	r.mu.Unlock()
	if handler != nil {
		return handler(ctx, req)
	}
	return &sdk.ElicitResult{
		Action: "decline",
		Content: map[string]any{
			"reason": "Interactive MCP elicitation UI is not implemented in the left panel yet",
		},
	}, nil
}

type authRoundTripper struct {
	base    http.RoundTripper
	headers map[string]string
	token   string
}

func (r *authRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	base := r.base
	if base == nil {
		base = http.DefaultTransport
	}
	next := req.Clone(req.Context())
	next.Header = req.Header.Clone()
	for k, v := range r.headers {
		key := strings.TrimSpace(k)
		if key == "" {
			continue
		}
		next.Header.Set(key, v)
	}
	if token := strings.TrimSpace(r.token); token != "" {
		next.Header.Set("Authorization", "Bearer "+token)
	}
	return base.RoundTrip(next)
}

func parseConfig(configJSON string) []ServerConfig {
	trimmed := strings.TrimSpace(configJSON)
	if trimmed == "" || trimmed == "[]" || trimmed == "null" {
		return nil
	}
	var cfgs []ServerConfig
	if err := json.Unmarshal([]byte(trimmed), &cfgs); err != nil {
		return nil
	}
	out := make([]ServerConfig, 0, len(cfgs))
	for _, cfg := range cfgs {
		cfg.ID = strings.TrimSpace(cfg.ID)
		cfg.Label = strings.TrimSpace(cfg.Label)
		cfg.URL = strings.TrimSpace(cfg.URL)
		if cfg.ID == "" || cfg.URL == "" {
			continue
		}
		if cfg.Headers == nil {
			cfg.Headers = map[string]string{}
		}
		out = append(out, cfg)
	}
	return out
}

func normalizeArgs(in map[string]any) map[string]any {
	if in == nil {
		return map[string]any{}
	}
	return in
}

func contentToText(content sdk.Content) string {
	switch item := content.(type) {
	case *sdk.TextContent:
		return item.Text
	case *sdk.ImageContent:
		return fmt.Sprintf("[image %s, %d bytes]", item.MIMEType, len(item.Data))
	case *sdk.AudioContent:
		return fmt.Sprintf("[audio %s, %d bytes]", item.MIMEType, len(item.Data))
	case *sdk.ResourceLink:
		return fmt.Sprintf("%s (%s)", firstNonEmpty(item.Title, item.Name), item.URI)
	case *sdk.EmbeddedResource:
		if item.Resource == nil {
			return "[resource]"
		}
		if item.Resource.Text != "" {
			return item.Resource.Text
		}
		if len(item.Resource.Blob) > 0 {
			return fmt.Sprintf("[resource %s, %d bytes]", item.Resource.URI, len(item.Resource.Blob))
		}
		return item.Resource.URI
	case *sdk.ToolUseContent:
		return fmt.Sprintf("[tool use %s]", item.Name)
	case *sdk.ToolResultContent:
		return joinContent(item.Content)
	default:
		return ""
	}
}

func joinContent(content []sdk.Content) string {
	parts := make([]string, 0, len(content))
	for _, item := range content {
		text := strings.TrimSpace(contentToText(item))
		if text == "" {
			continue
		}
		parts = append(parts, text)
	}
	return strings.Join(parts, "\n")
}

func asMap(value any) map[string]any {
	if value == nil {
		return nil
	}
	if mapped, ok := value.(map[string]any); ok {
		return mapped
	}
	raw, err := json.Marshal(value)
	if err != nil {
		return nil
	}
	var out map[string]any
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil
	}
	return out
}

func configHash(cfg ServerConfig) string {
	raw, _ := json.Marshal(cfg)
	return fmt.Sprintf("%x", sha1.Sum(raw))
}

func serverLabel(cfg ServerConfig) string {
	return firstNonEmpty(cfg.Label, cfg.ID)
}

func builtinServerSnapshot() ServerSnapshot {
	return ServerSnapshot{
		ID:            "builtin",
		Label:         "Leftpanel Built-ins",
		URL:           "builtin://leftpanel",
		Enabled:       true,
		Connected:     true,
		Status:        "connected",
		ServerName:    "leftpanel-builtins",
		ServerVersion: clientVersion,
		ToolCount:     len(builtinToolSnapshots()),
		Capabilities: map[string]any{
			"tools": true,
		},
	}
}

func builtinToolSnapshots() []ToolSnapshot {
	return []ToolSnapshot{
		{
			ServerID:      "builtin",
			ServerLabel:   "Leftpanel Built-ins",
			Name:          "shell_command",
			QualifiedName: "builtin__shell_command",
			Title:         "Shell command",
			Description:   "Run a bubblewrap sandbox command. Inside the sandbox, $HOME and /workspace are the same writable directory; ~/.cache and ~/.local are also writable, and other host paths are read-only or unavailable.",
			InputSchema: map[string]any{
				"type": "object",
				"properties": map[string]any{
					"command": map[string]any{
						"type":        "string",
						"description": "The shell script to execute in the user's default shell.",
					},
					"workdir": map[string]any{
						"type":        "string",
						"description": "The working directory to execute the command in.",
					},
					"timeout_ms": map[string]any{
						"type":        "number",
						"description": "Optional timeout in milliseconds, capped at 15000.",
					},
					"login": map[string]any{
						"type":        "boolean",
						"description": "Whether to run the shell with login shell semantics. Accepted for Codex compatibility; leftpanel currently always runs bash -lc inside the sandbox.",
					},
					"sandbox_permissions": map[string]any{
						"type":        "string",
						"description": "Accepted for Codex compatibility. Leftpanel always uses its configured bubblewrap sandbox.",
					},
					"justification": map[string]any{
						"type":        "string",
						"description": "Accepted for Codex compatibility when sandbox_permissions would request escalation.",
					},
					"prefix_rule": map[string]any{
						"type":        "array",
						"items":       map[string]any{"type": "string"},
						"description": "Accepted for Codex compatibility; leftpanel does not persist shell approval rules yet.",
					},
				},
				"required": []any{"command"},
			},
		},
		{
			ServerID:      "builtin",
			ServerLabel:   "Leftpanel Built-ins",
			Name:          "apply_patch",
			QualifiedName: "builtin__apply_patch",
			Title:         "Apply patch",
			Description:   "Edit files in the sandbox using the Codex apply_patch format. File paths must be relative to $HOME / /workspace.",
			InputSchema: map[string]any{
				"type": "object",
				"properties": map[string]any{
					"input": map[string]any{
						"type":        "string",
						"description": "Full apply_patch payload.",
					},
				},
				"required": []any{"input"},
			},
			OutputSchema: map[string]any{
				"type": "object",
				"properties": map[string]any{
					"changed_files": map[string]any{
						"type":  "array",
						"items": map[string]any{"type": "string"},
					},
				},
			},
		},
	}
}

func callBuiltinTool(toolName string, arguments map[string]any) shared.ToolResult {
	switch strings.TrimSpace(toolName) {
	case "shell_command", "shell_exec":
		return callBuiltinShellExec(strings.TrimSpace(toolName), arguments)
	case "apply_patch":
		return callBuiltinApplyPatch(arguments)
	default:
		return shared.ToolResult{
			Name:    toolName,
			Text:    "Unknown built-in tool: " + toolName,
			IsError: true,
		}
	}
}

func isBuiltinTool(toolName string) bool {
	switch strings.TrimSpace(toolName) {
	case "shell_command", "shell_exec", "apply_patch":
		return true
	default:
		return false
	}
}

func callBuiltinShellExec(toolName string, arguments map[string]any) shared.ToolResult {
	if toolName == "" {
		toolName = "shell_command"
	}
	command := strings.TrimSpace(fmt.Sprint(arguments["command"]))
	if command == "" || command == "<nil>" {
		return shellError(toolName, "command is required")
	}

	cwd := firstNonEmpty(stringArgument(arguments, "workdir"), stringArgument(arguments, "cwd"))

	timeout := 15 * time.Second
	if raw, ok := numericArgument(arguments["timeout_ms"]); ok && raw > 0 {
		timeout = time.Duration(raw) * time.Millisecond
	}
	if timeout > 15*time.Second {
		timeout = 15 * time.Second
	}

	sandboxRoot, err := shellSandboxRoot()
	if err != nil {
		return shellError(toolName, err.Error())
	}
	if err := os.MkdirAll(sandboxRoot, 0o755); err != nil {
		return shellError(toolName, err.Error())
	}
	hostHome, err := os.UserHomeDir()
	if err != nil {
		return shellError(toolName, err.Error())
	}
	if err := os.MkdirAll(filepath.Join(hostHome, ".cache"), 0o755); err != nil {
		return shellError(toolName, err.Error())
	}
	if err := os.MkdirAll(filepath.Join(hostHome, ".local"), 0o755); err != nil {
		return shellError(toolName, err.Error())
	}
	cwd, err = normalizeShellCwd(cwd, hostHome)
	if err != nil {
		return shellError(toolName, err.Error())
	}

	start := time.Now()
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	args := []string{
		"--unshare-all",
		"--share-net",
		"--die-with-parent",
		"--new-session",
		"--proc", "/proc",
		"--dev", "/dev",
		"--tmpfs", "/tmp",
		"--dir", "/run",
		"--ro-bind-try", "/run/systemd/resolve", "/run/systemd/resolve",
		"--dir", "/home",
		"--bind", sandboxRoot, hostHome,
		"--dir", filepath.Join(hostHome, ".cache"),
		"--bind", filepath.Join(hostHome, ".cache"), filepath.Join(hostHome, ".cache"),
		"--dir", filepath.Join(hostHome, ".local"),
		"--bind", filepath.Join(hostHome, ".local"), filepath.Join(hostHome, ".local"),
		"--symlink", hostHome, "/workspace",
		"--ro-bind", "/usr", "/usr",
		"--ro-bind", "/bin", "/bin",
		"--ro-bind", "/lib", "/lib",
		"--ro-bind-try", "/lib64", "/lib64",
		"--ro-bind", "/etc", "/etc",
		"--setenv", "HOME", hostHome,
		"--setenv", "USER", os.Getenv("USER"),
		"--setenv", "LOGNAME", os.Getenv("USER"),
		"--setenv", "XDG_CACHE_HOME", filepath.Join(hostHome, ".cache"),
		"--setenv", "PATH", firstNonEmpty(os.Getenv("PATH"), "/usr/local/bin:/usr/bin:/bin"),
		"--setenv", "SSL_CERT_FILE", firstNonEmpty(os.Getenv("SSL_CERT_FILE"), "/etc/ssl/certs/ca-certificates.crt"),
		"--chdir", cwd,
		"--remount-ro", "/",
		"--",
		"/bin/bash", "-lc", command,
	}
	cmd := exec.CommandContext(ctx, "bwrap", args...)
	var stdoutBuf, stderrBuf bytes.Buffer
	cmd.Stdout = &stdoutBuf
	cmd.Stderr = &stderrBuf
	err = cmd.Run()
	timedOut := ctx.Err() == context.DeadlineExceeded
	durationMS := time.Since(start).Milliseconds()
	if timedOut {
		return shared.ToolResult{
			Name: toolName,
			Text: codexShellCommandOutput(124, durationMS, "command timed out"),
			Data: map[string]any{
				"stdout":       "",
				"stderr":       "",
				"exit_code":    124,
				"timed_out":    true,
				"truncated":    false,
				"cwd":          cwd,
				"workdir":      cwd,
				"duration_ms":  durationMS,
				"sandbox_home": hostHome,
				"workspace":    "/workspace",
			},
			IsError: true,
		}
	}

	stdout, stdoutTruncated := truncateOutput(stdoutBuf.String(), 24*1024)
	stderr, stderrTruncated := truncateOutput(stderrBuf.String(), 8*1024)
	exitCode := 0
	if err != nil {
		exitCode = 1
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			exitCode = exitErr.ExitCode()
		} else if stderr == "" {
			stderr = err.Error()
		}
	}
	data := map[string]any{
		"stdout":       stdout,
		"stderr":       stderr,
		"exit_code":    exitCode,
		"timed_out":    false,
		"truncated":    stdoutTruncated || stderrTruncated,
		"cwd":          cwd,
		"workdir":      cwd,
		"duration_ms":  durationMS,
		"sandbox_home": hostHome,
		"workspace":    "/workspace",
	}
	output := firstNonEmpty(stdout, stderr)
	return shared.ToolResult{
		Name:    toolName,
		Text:    codexShellCommandOutput(exitCode, durationMS, output),
		Data:    data,
		IsError: exitCode != 0,
	}
}

func codexShellCommandOutput(exitCode int, durationMS int64, output string) string {
	durationSeconds := (float64(durationMS) / 1000.0)
	rounded := float64(int(durationSeconds*10+0.5)) / 10
	return fmt.Sprintf("Exit code: %d\nWall time: %.1f seconds\nOutput:\n%s", exitCode, rounded, output)
}

const applyPatchLarkGrammar = `start: begin_patch hunk+ end_patch
begin_patch: "*** Begin Patch" LF
end_patch: "*** End Patch" LF?

hunk: add_hunk | delete_hunk | update_hunk
add_hunk: "*** Add File: " filename LF add_line+
delete_hunk: "*** Delete File: " filename LF
update_hunk: "*** Update File: " filename LF change_move? change?

filename: /(.+)/
add_line: "+" /(.*)/ LF -> line

change_move: "*** Move to: " filename LF
change: (change_context | change_line)+ eof_line?
change_context: ("@@" | "@@ " /(.+)/) LF
change_line: ("+" | "-" | " ") /(.*)/ LF
eof_line: "*** End of File" LF

%import common.LF`

func callBuiltinApplyPatch(arguments map[string]any) shared.ToolResult {
	input := strings.TrimSpace(fmt.Sprint(arguments["input"]))
	if input == "" || input == "<nil>" {
		return shellError("apply_patch", "input is required")
	}
	sandboxRoot, err := shellSandboxRoot()
	if err != nil {
		return shellError("apply_patch", err.Error())
	}
	if err := os.MkdirAll(sandboxRoot, 0o755); err != nil {
		return shellError("apply_patch", err.Error())
	}

	changed, err := applyPatchToSandbox(sandboxRoot, input)
	if err != nil {
		return shellError("apply_patch", err.Error())
	}
	return shared.ToolResult{
		Name: "apply_patch",
		Text: "Done!",
		Data: map[string]any{
			"changed_files": changed,
		},
	}
}

func applyPatchToSandbox(sandboxRoot string, input string) ([]string, error) {
	lines := strings.SplitAfter(input, "\n")
	if len(lines) < 2 || strings.TrimRight(lines[0], "\n") != "*** Begin Patch" {
		return nil, fmt.Errorf("apply_patch input must start with *** Begin Patch")
	}
	i := 1
	changed := []string{}
	for i < len(lines) {
		line := strings.TrimRight(lines[i], "\n")
		switch {
		case line == "*** End Patch":
			return changed, nil
		case strings.HasPrefix(line, "*** Add File: "):
			path := strings.TrimSpace(strings.TrimPrefix(line, "*** Add File: "))
			i++
			content := strings.Builder{}
			for i < len(lines) {
				next := strings.TrimRight(lines[i], "\n")
				if strings.HasPrefix(next, "*** ") {
					break
				}
				if !strings.HasPrefix(lines[i], "+") {
					return nil, fmt.Errorf("add file lines must start with +")
				}
				content.WriteString(strings.TrimPrefix(lines[i], "+"))
				i++
			}
			target, err := sandboxPatchPath(sandboxRoot, path)
			if err != nil {
				return nil, err
			}
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return nil, err
			}
			if err := os.WriteFile(target, []byte(content.String()), 0o644); err != nil {
				return nil, err
			}
			changed = append(changed, filepath.ToSlash(filepath.Clean(path)))
		case strings.HasPrefix(line, "*** Delete File: "):
			path := strings.TrimSpace(strings.TrimPrefix(line, "*** Delete File: "))
			target, err := sandboxPatchPath(sandboxRoot, path)
			if err != nil {
				return nil, err
			}
			if err := os.Remove(target); err != nil {
				return nil, err
			}
			changed = append(changed, filepath.ToSlash(filepath.Clean(path)))
			i++
		case strings.HasPrefix(line, "*** Update File: "):
			path := strings.TrimSpace(strings.TrimPrefix(line, "*** Update File: "))
			i++
			newPath := ""
			if i < len(lines) && strings.HasPrefix(strings.TrimRight(lines[i], "\n"), "*** Move to: ") {
				newPath = strings.TrimSpace(strings.TrimPrefix(strings.TrimRight(lines[i], "\n"), "*** Move to: "))
				i++
			}
			target, err := sandboxPatchPath(sandboxRoot, path)
			if err != nil {
				return nil, err
			}
			raw, err := os.ReadFile(target)
			if err != nil {
				return nil, err
			}
			content := string(raw)
			for i < len(lines) {
				next := strings.TrimRight(lines[i], "\n")
				if strings.HasPrefix(next, "*** ") {
					break
				}
				if !strings.HasPrefix(next, "@@") {
					return nil, fmt.Errorf("update hunks must start with @@")
				}
				i++
				oldText := strings.Builder{}
				newText := strings.Builder{}
				for i < len(lines) {
					hunkLine := strings.TrimRight(lines[i], "\n")
					if strings.HasPrefix(hunkLine, "*** ") || strings.HasPrefix(hunkLine, "@@") {
						break
					}
					switch {
					case strings.HasPrefix(lines[i], "-"):
						oldText.WriteString(strings.TrimPrefix(lines[i], "-"))
					case strings.HasPrefix(lines[i], "+"):
						newText.WriteString(strings.TrimPrefix(lines[i], "+"))
					case strings.HasPrefix(lines[i], " "):
						text := strings.TrimPrefix(lines[i], " ")
						oldText.WriteString(text)
						newText.WriteString(text)
					default:
						return nil, fmt.Errorf("update hunk lines must start with space, -, or +")
					}
					i++
				}
				old := oldText.String()
				if old == "" {
					return nil, fmt.Errorf("update hunk must include context or removed lines")
				}
				if !strings.Contains(content, old) {
					return nil, fmt.Errorf("update hunk did not match %s", path)
				}
				content = strings.Replace(content, old, newText.String(), 1)
			}
			writeTarget := target
			changedPath := path
			if newPath != "" {
				writeTarget, err = sandboxPatchPath(sandboxRoot, newPath)
				if err != nil {
					return nil, err
				}
				changedPath = newPath
			}
			if err := os.MkdirAll(filepath.Dir(writeTarget), 0o755); err != nil {
				return nil, err
			}
			if err := os.WriteFile(writeTarget, []byte(content), 0o644); err != nil {
				return nil, err
			}
			if newPath != "" && writeTarget != target {
				if err := os.Remove(target); err != nil {
					return nil, err
				}
			}
			changed = append(changed, filepath.ToSlash(filepath.Clean(changedPath)))
		default:
			return nil, fmt.Errorf("unsupported apply_patch line: %s", line)
		}
	}
	return nil, fmt.Errorf("apply_patch input must end with *** End Patch")
}

func sandboxPatchPath(sandboxRoot string, path string) (string, error) {
	path = strings.TrimSpace(path)
	if path == "" {
		return "", fmt.Errorf("patch path is required")
	}
	if filepath.IsAbs(path) {
		return "", fmt.Errorf("patch paths must be relative")
	}
	root, err := filepath.Abs(sandboxRoot)
	if err != nil {
		return "", err
	}
	clean := filepath.Clean(path)
	if clean == "." || clean == ".." || strings.HasPrefix(clean, ".."+string(os.PathSeparator)) {
		return "", fmt.Errorf("patch paths must stay inside the sandbox")
	}
	target := filepath.Join(root, clean)
	if !pathWithinRoot(root, target) {
		return "", fmt.Errorf("patch paths must stay inside the sandbox")
	}
	if info, err := os.Lstat(target); err == nil && info.Mode()&os.ModeSymlink != 0 {
		return "", fmt.Errorf("patch paths must not target symlinks")
	}

	existing := filepath.Dir(target)
	for {
		if _, err := os.Lstat(existing); err == nil {
			break
		}
		next := filepath.Dir(existing)
		if next == existing {
			return "", fmt.Errorf("patch parent does not exist inside the sandbox")
		}
		existing = next
	}
	resolved, err := filepath.EvalSymlinks(existing)
	if err != nil {
		return "", err
	}
	if !pathWithinRoot(root, resolved) {
		return "", fmt.Errorf("patch paths must not traverse symlinks outside the sandbox")
	}
	return target, nil
}

func pathWithinRoot(root string, target string) bool {
	rel, err := filepath.Rel(root, target)
	if err != nil {
		return false
	}
	return rel == "." || (!strings.HasPrefix(rel, ".."+string(os.PathSeparator)) && rel != "..")
}

func normalizeShellCwd(cwd string, home string) (string, error) {
	if cwd == "" || cwd == "<nil>" {
		return home, nil
	}
	if strings.HasPrefix(cwd, "/workspace") {
		cwd = filepath.Join(home, strings.TrimPrefix(cwd, "/workspace"))
	}
	if !filepath.IsAbs(cwd) {
		cwd = filepath.Join(home, cwd)
	}
	clean := filepath.Clean(cwd)
	if clean == home || strings.HasPrefix(clean, home+string(os.PathSeparator)) || clean == "/tmp" || strings.HasPrefix(clean, "/tmp/") {
		return clean, nil
	}
	return "", fmt.Errorf("cwd must be inside %s, /workspace, or /tmp", home)
}

func shellError(name, text string) shared.ToolResult {
	return shared.ToolResult{Name: name, Text: text, IsError: true}
}

func numericArgument(v any) (int64, bool) {
	switch x := v.(type) {
	case int:
		return int64(x), true
	case int64:
		return x, true
	case float64:
		return int64(x), true
	case json.Number:
		n, err := x.Int64()
		return n, err == nil
	default:
		return 0, false
	}
}

func shellSandboxRoot() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, "tmp", "ai-sandbox"), nil
}

func stringArgument(args map[string]any, key string) string {
	if args == nil {
		return ""
	}
	value, ok := args[key]
	if !ok || value == nil {
		return ""
	}
	return strings.TrimSpace(fmt.Sprint(value))
}

func truncateOutput(text string, limit int) (string, bool) {
	if len(text) <= limit {
		return text, false
	}
	return text[:limit] + "\n[truncated]", true
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func mustJSON(value any) string {
	raw, _ := json.Marshal(value)
	return string(raw)
}

func qualifiedToolName(serverID string, toolName string) string {
	return strings.TrimSpace(serverID) + "__" + strings.TrimSpace(toolName)
}

func splitQualifiedToolName(serverID string, toolName string) (string, string) {
	if strings.TrimSpace(serverID) != "" {
		return strings.TrimSpace(serverID), strings.TrimSpace(toolName)
	}
	parts := strings.SplitN(strings.TrimSpace(toolName), "__", 2)
	if len(parts) == 2 && parts[0] != "" && parts[1] != "" {
		return parts[0], parts[1]
	}
	return strings.TrimSpace(serverID), strings.TrimSpace(toolName)
}
