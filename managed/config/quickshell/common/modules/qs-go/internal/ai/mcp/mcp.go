package mcp

import (
	"context"
	"crypto/sha1"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
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
		out = append(out, shared.ToolDescriptor{
			Name:        firstNonEmpty(tool.QualifiedName, qualifiedToolName(tool.ServerID, tool.Name)),
			Title:       tool.Title,
			Description: tool.Description,
			InputSchema: tool.InputSchema,
			ServerID:    tool.ServerID,
			ServerLabel: tool.ServerLabel,
		})
	}
	if len(out) == 0 && strings.TrimSpace(snapshot.Error) != "" {
		return nil, errors.New(snapshot.Error)
	}
	return out, nil
}

func CallTool(configJSON string, serverID string, toolName string, arguments map[string]any) (shared.ToolResult, error) {
	serverID, toolName = splitQualifiedToolName(serverID, toolName)
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
		Servers:   make([]ServerSnapshot, 0, len(r.conns)),
		Tools:     []ToolSnapshot{},
		Prompts:   []PromptSnapshot{},
		Resources: []ResourceSnapshot{},
		Status:    "ready",
	}
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
