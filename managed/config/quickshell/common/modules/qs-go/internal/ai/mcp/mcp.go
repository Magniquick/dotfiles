package mcp

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log"
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
	"qs-go/internal/secrets"
)

const clientVersion = "v1.0.0"
const hostedTodoistMCPURL = "https://ai.todoist.net/mcp"
const remoteCatalogDeferToolThreshold = 10
const remoteCatalogDeferByteThreshold = 24 * 1024
const remoteCatalogCacheRefreshAfter = 6 * time.Hour
const remoteCatalogCacheHardExpiry = 24 * time.Hour
const remoteCatalogCacheVersion = 1

// ServerConfig describes one configured MCP server.
type ServerConfig struct {
	ID          string            `json:"id"`
	Label       string            `json:"label,omitempty"`
	URL         string            `json:"url"`
	Enabled     bool              `json:"enabled"`
	AutoConnect bool              `json:"auto_connect,omitempty"`
	BearerToken string            `json:"bearer_token,omitempty"`
	Headers     map[string]string `json:"headers,omitempty"`
}

// ServerSnapshot captures the current connection state for one MCP server.
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

// ToolSnapshot describes an MCP tool exposed to model providers.
type ToolSnapshot struct {
	ServerID      string         `json:"server_id"`
	ServerLabel   string         `json:"server_label"`
	Name          string         `json:"name"`
	QualifiedName string         `json:"qualified_name"`
	Title         string         `json:"title,omitempty"`
	Description   string         `json:"description,omitempty"`
	InputSchema   map[string]any `json:"input_schema,omitempty"`
	OutputSchema  map[string]any `json:"output_schema,omitempty"`
	ReadOnly      bool           `json:"read_only,omitempty"`
	Destructive   bool           `json:"destructive,omitempty"`
	OpenWorld     bool           `json:"open_world,omitempty"`
	Idempotent    bool           `json:"idempotent,omitempty"`
	Risk          string         `json:"risk,omitempty"`
}

// PromptSnapshot describes an MCP prompt exposed by a server.
type PromptSnapshot struct {
	ServerID    string      `json:"server_id"`
	ServerLabel string      `json:"server_label"`
	Name        string      `json:"name"`
	Title       string      `json:"title,omitempty"`
	Description string      `json:"description,omitempty"`
	Arguments   []PromptArg `json:"arguments,omitempty"`
}

// PromptArg describes one prompt argument.
type PromptArg struct {
	Name        string `json:"name"`
	Description string `json:"description,omitempty"`
	Required    bool   `json:"required"`
}

// ResourceSnapshot describes an MCP resource exposed by a server.
type ResourceSnapshot struct {
	ServerID    string `json:"server_id"`
	ServerLabel string `json:"server_label"`
	URI         string `json:"uri"`
	Name        string `json:"name"`
	Title       string `json:"title,omitempty"`
	Description string `json:"description,omitempty"`
	MIMEType    string `json:"mime_type,omitempty"`
}

// PromptResult is the provider-facing result of reading an MCP prompt.
type PromptResult struct {
	ServerID    string        `json:"server_id"`
	ServerLabel string        `json:"server_label"`
	Name        string        `json:"name"`
	Description string        `json:"description,omitempty"`
	Messages    []PromptEntry `json:"messages"`
}

// PromptEntry is one prompt message returned from an MCP server.
type PromptEntry struct {
	Role string `json:"role"`
	Text string `json:"text"`
}

// ResourceReadResult is the provider-facing result of reading MCP resources.
type ResourceReadResult struct {
	ServerID    string          `json:"server_id"`
	ServerLabel string          `json:"server_label"`
	Contents    []ResourceEntry `json:"contents"`
}

// ResourceEntry is one MCP resource payload.
type ResourceEntry struct {
	URI      string `json:"uri"`
	MIMEType string `json:"mime_type,omitempty"`
	Text     string `json:"text,omitempty"`
	BlobB64  string `json:"blob_b64,omitempty"`
}

// Snapshot is the aggregate state of configured MCP servers.
type Snapshot struct {
	Servers   []ServerSnapshot   `json:"servers"`
	Tools     []ToolSnapshot     `json:"tools"`
	Prompts   []PromptSnapshot   `json:"prompts"`
	Resources []ResourceSnapshot `json:"resources"`
	Status    string             `json:"status"`
	Error     string             `json:"error,omitempty"`
}

// SamplingHandler handles MCP sampling requests from servers.
type SamplingHandler func(
	context.Context,
	*sdk.CreateMessageWithToolsRequest,
) (*sdk.CreateMessageWithToolsResult, error)

// ElicitationHandler handles MCP elicitation requests from servers.
type ElicitationHandler func(context.Context, *sdk.ElicitRequest) (*sdk.ElicitResult, error)

type runtime struct {
	mu sync.Mutex

	configs    map[string]ServerConfig
	conns      map[string]*serverConn
	refreshing map[string]bool

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
	cachedAt  time.Time
}

type cachedServerSnapshot struct {
	Version   int                `json:"version"`
	Hash      string             `json:"hash"`
	CachedAt  time.Time          `json:"cached_at"`
	Snapshot  ServerSnapshot     `json:"snapshot"`
	Tools     []ToolSnapshot     `json:"tools"`
	Prompts   []PromptSnapshot   `json:"prompts,omitempty"`
	Resources []ResourceSnapshot `json:"resources,omitempty"`
}

var defaultRuntime = &runtime{
	configs:    map[string]ServerConfig{},
	conns:      map[string]*serverConn{},
	refreshing: map[string]bool{},
}

// Refresh reconnects configured servers and returns a JSON snapshot.
func Refresh(configJSON string) string {
	snapshot := defaultRuntime.refresh(configuredServers(configJSON))
	return mustJSON(snapshot)
}

// ToolDescriptors returns model-provider tool descriptors for configured MCP servers.
func ToolDescriptors(configJSON string) ([]shared.ToolDescriptor, error) {
	snapshot := defaultRuntime.snapshotForToolDescriptors(configuredServers(configJSON))
	log.Printf(
		"qs-go ai/mcp: refresh status=%s error=%q servers=[%s] tools=%d",
		snapshot.Status,
		snapshot.Error,
		serverSummary(snapshot.Servers),
		len(snapshot.Tools),
	)
	return descriptorsFromSnapshot(snapshot)
}

func descriptorsFromSnapshot(snapshot Snapshot) ([]shared.ToolDescriptor, error) {
	servers := make(map[string]ServerSnapshot, len(snapshot.Servers))
	for _, server := range snapshot.Servers {
		servers[strings.TrimSpace(server.ID)] = server
	}
	deferRemoteCatalog := shouldDeferRemoteCatalog(snapshot)
	out := make([]shared.ToolDescriptor, 0, len(snapshot.Tools))
	for _, tool := range snapshot.Tools {
		server := servers[strings.TrimSpace(tool.ServerID)]
		name := firstNonEmpty(tool.QualifiedName, qualifiedToolName(tool.ServerID, tool.Name))
		if isLocalToolServer(tool.ServerID) {
			name = strings.TrimSpace(tool.Name)
		}
		descriptor := shared.ToolDescriptor{
			Name:             name,
			Title:            tool.Title,
			Description:      tool.Description,
			InputSchema:      tool.InputSchema,
			Kind:             builtinToolKind(tool),
			Format:           builtinToolFormat(tool),
			ReadOnly:         tool.ReadOnly,
			Destructive:      tool.Destructive,
			OpenWorld:        tool.OpenWorld,
			Idempotent:       tool.Idempotent,
			Risk:             firstNonEmpty(tool.Risk, riskForTool(tool.ReadOnly, tool.Destructive)),
			ServerID:         tool.ServerID,
			ServerLabel:      tool.ServerLabel,
			FullInstructions: strings.TrimSpace(server.Instructions),
		}
		if !isLocalToolServer(tool.ServerID) {
			descriptor.Namespace = toolNamespace(tool.ServerID)
			descriptor.NamespaceDescription = shortNamespaceDescription(server)
			descriptor.DeferLoading = deferRemoteCatalog
			descriptor.SearchText = descriptorSearchText(server, tool)
		}
		out = append(out, descriptor)
	}
	if len(out) == 0 && strings.TrimSpace(snapshot.Error) != "" {
		return nil, errors.New(snapshot.Error)
	}
	return out, nil
}

func shouldDeferRemoteCatalog(snapshot Snapshot) bool {
	remoteToolCount := 0
	for _, server := range snapshot.Servers {
		if isLocalToolServer(server.ID) {
			continue
		}
		if server.ToolCount > 0 {
			remoteToolCount += server.ToolCount
		}
	}
	if remoteToolCount == 0 {
		for _, tool := range snapshot.Tools {
			if !isLocalToolServer(tool.ServerID) {
				remoteToolCount++
			}
		}
	}
	if remoteToolCount > remoteCatalogDeferToolThreshold {
		return true
	}

	remoteTools := make([]ToolSnapshot, 0, len(snapshot.Tools))
	for _, tool := range snapshot.Tools {
		if !isLocalToolServer(tool.ServerID) {
			remoteTools = append(remoteTools, tool)
		}
	}
	data, err := json.Marshal(remoteTools)
	return err == nil && len(data) > remoteCatalogDeferByteThreshold
}

func shortNamespaceDescription(server ServerSnapshot) string {
	switch strings.TrimSpace(server.ID) {
	case "todoist":
		return "Todoist tasks, projects, comments, labels, and account tools."
	case emailServerID:
		return "Read-only email account, search, and message-reading tools."
	}
	label := firstNonEmpty(server.Label, server.ServerName, server.ID)
	if label == "" {
		return "MCP tools."
	}
	return label + " MCP tools."
}

func descriptorSearchText(server ServerSnapshot, tool ToolSnapshot) string {
	parts := []string{}
	for _, value := range []string{
		server.Label,
		server.ServerName,
		server.Instructions,
		tool.Title,
		tool.Description,
		tool.Name,
	} {
		value = strings.TrimSpace(value)
		if value != "" {
			parts = append(parts, value)
		}
	}
	return strings.Join(parts, "\n")
}

func riskForTool(readOnly bool, destructive bool) string {
	if readOnly {
		return "read"
	}
	if destructive {
		return "destructive"
	}
	return "write"
}

func serverSummary(servers []ServerSnapshot) string {
	parts := make([]string, 0, len(servers))
	for _, server := range servers {
		id := strings.TrimSpace(server.ID)
		if id == "" {
			id = strings.TrimSpace(server.Label)
		}
		status := strings.TrimSpace(server.Status)
		if status == "" {
			status = "unknown"
		}
		part := fmt.Sprintf("%s:%s:tools=%d", id, status, server.ToolCount)
		if strings.TrimSpace(server.Error) != "" {
			part += ":error"
		}
		parts = append(parts, part)
	}
	slices.Sort(parts)
	return strings.Join(parts, ",")
}

func mapKeys(values map[string]any) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	slices.Sort(keys)
	return keys
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

// CallTool invokes a local or remote MCP tool.
func CallTool(
	configJSON string,
	serverID string,
	toolName string,
	arguments map[string]any,
) (shared.ToolResult, error) {
	serverID, toolName = splitQualifiedToolName(serverID, toolName)
	log.Printf("qs-go ai/mcp: call namespace_server=%q tool=%q arg_keys=%v", serverID, toolName, mapKeys(arguments))
	if strings.TrimSpace(serverID) == emailServerID || (strings.TrimSpace(serverID) == "" && isEmailTool(toolName)) {
		return callEmailTool(toolName, arguments), nil
	}
	if strings.TrimSpace(serverID) == "builtin" || (strings.TrimSpace(serverID) == "" && isBuiltinTool(toolName)) {
		return callBuiltinTool(toolName, arguments), nil
	}

	cfgs := configuredServers(configJSON)
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

	data := asMap(res.StructuredContent)

	return shared.ToolResult{
		Name:              toolName,
		Text:              joinContent(res.Content),
		Data:              data,
		Content:           contentAsMaps(res.Content),
		StructuredContent: data,
		Meta:              map[string]any(res.Meta),
		IsError:           res.IsError,
	}, nil
}

// GetPrompt reads an MCP prompt and returns a JSON result.
func GetPrompt(configJSON string, serverID string, promptName string, argsJSON string) string {
	args := map[string]string{}
	if strings.TrimSpace(argsJSON) != "" {
		_ = json.Unmarshal([]byte(argsJSON), &args)
	}

	cfgs := configuredServers(configJSON)
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

// ReadResource reads an MCP resource and returns a JSON result.
func ReadResource(configJSON string, serverID string, uri string) string {
	cfgs := configuredServers(configJSON)
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

// WithStreamHandlers installs temporary MCP sampling and elicitation handlers.
func WithStreamHandlers(_ string, sampling SamplingHandler, elicitation ElicitationHandler, fn func() error) error {
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

func (r *runtime) snapshotForToolDescriptors(cfgs []ServerConfig) Snapshot {
	var refreshCfgs []ServerConfig

	r.mu.Lock()
	r.reconcileConfigsLocked(cfgs)
	for _, cfg := range cfgs {
		id := strings.TrimSpace(cfg.ID)
		if id == "" {
			continue
		}
		if !cfg.Enabled {
			r.conns[id] = disabledServerConn(cfg)
			continue
		}

		hash := configHash(cfg)
		existing := r.conns[id]
		if existing != nil && existing.hash == hash && existing.session != nil {
			continue
		}
		if existing != nil && existing.hash == hash && !existing.cachedAt.IsZero() {
			age := time.Since(existing.cachedAt)
			if age < remoteCatalogCacheHardExpiry {
				if age >= remoteCatalogCacheRefreshAfter {
					refreshCfgs = append(refreshCfgs, cfg)
				}
				continue
			}
		}
		if existing != nil && existing.session != nil {
			_ = existing.session.Close()
		}

		conn, age, ok := loadCachedServerSnapshot(cfg, hash, time.Now())
		if ok {
			r.conns[id] = conn
			if age >= remoteCatalogCacheRefreshAfter {
				refreshCfgs = append(refreshCfgs, cfg)
			}
			continue
		}

		r.conns[id] = refreshingServerConn(cfg, hash)
		refreshCfgs = append(refreshCfgs, cfg)
	}
	snapshot := r.snapshotLocked()
	r.mu.Unlock()

	for _, cfg := range refreshCfgs {
		r.startBackgroundRefresh(cfg)
	}
	return snapshot
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

	r.reconcileConfigsLocked(cfgs)
	var errs []string
	for _, cfg := range cfgs {
		if !cfg.Enabled {
			r.conns[cfg.ID] = disabledServerConn(cfg)
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
			continue
		}
		if err := saveCachedServerSnapshot(cfg, hash, conn, time.Now()); err != nil {
			log.Printf("qs-go ai/mcp: failed to cache %s catalog: %v", cfg.ID, err)
		}
	}

	snapshot := r.snapshotLocked()
	if len(errs) > 0 {
		return snapshot, errors.New(strings.Join(errs, "; "))
	}
	return snapshot, nil
}

func (r *runtime) reconcileConfigsLocked(cfgs []ServerConfig) {
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
	if r.refreshing == nil {
		r.refreshing = map[string]bool{}
	}
}

func disabledServerConn(cfg ServerConfig) *serverConn {
	return &serverConn{
		cfg: cfg,
		snapshot: ServerSnapshot{
			ID:      cfg.ID,
			Label:   serverLabel(cfg),
			URL:     cfg.URL,
			Enabled: cfg.Enabled,
			Status:  "disabled",
		},
	}
}

func refreshingServerConn(cfg ServerConfig, hash string) *serverConn {
	return &serverConn{
		cfg:  cfg,
		hash: hash,
		snapshot: ServerSnapshot{
			ID:      cfg.ID,
			Label:   serverLabel(cfg),
			URL:     cfg.URL,
			Enabled: cfg.Enabled,
			Status:  "refreshing",
		},
	}
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
		CreateMessageWithToolsHandler: func(
			ctx context.Context,
			req *sdk.CreateMessageWithToolsRequest,
		) (*sdk.CreateMessageWithToolsResult, error) {
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

func (r *runtime) startBackgroundRefresh(cfg ServerConfig) {
	hash := configHash(cfg)
	key := strings.TrimSpace(cfg.ID) + "@" + hash

	r.mu.Lock()
	if r.refreshing == nil {
		r.refreshing = map[string]bool{}
	}
	if r.refreshing[key] {
		r.mu.Unlock()
		return
	}
	r.refreshing[key] = true
	r.mu.Unlock()

	go func() {
		conn, err := r.connectServer(cfg, hash)
		if err == nil {
			if cacheErr := saveCachedServerSnapshot(cfg, hash, conn, time.Now()); cacheErr != nil {
				log.Printf("qs-go ai/mcp: failed to cache %s catalog: %v", cfg.ID, cacheErr)
			}
		} else {
			log.Printf("qs-go ai/mcp: async refresh failed for %s: %v", cfg.ID, err)
		}

		r.mu.Lock()
		defer r.mu.Unlock()
		delete(r.refreshing, key)
		current, ok := r.configs[strings.TrimSpace(cfg.ID)]
		if err != nil || !ok || configHash(current) != hash || !current.Enabled {
			if conn != nil && conn.session != nil {
				_ = conn.session.Close()
			}
			return
		}
		if existing := r.conns[strings.TrimSpace(cfg.ID)]; existing != nil && existing.session != nil {
			_ = existing.session.Close()
		}
		r.conns[strings.TrimSpace(cfg.ID)] = conn
	}()
}

func (r *runtime) connectServer(cfg ServerConfig, hash string) (*serverConn, error) {
	return r.connectLocked(cfg, hash)
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
				ReadOnly:      toolReadOnly(tool),
				Destructive:   toolDestructive(tool),
				OpenWorld:     toolOpenWorld(tool),
				Idempotent:    toolIdempotent(tool),
				Risk:          riskForTool(toolReadOnly(tool), toolDestructive(tool)),
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

func toolReadOnly(tool *sdk.Tool) bool {
	return tool != nil && tool.Annotations != nil && tool.Annotations.ReadOnlyHint
}

func toolDestructive(tool *sdk.Tool) bool {
	if tool == nil || tool.Annotations == nil {
		return true
	}
	if tool.Annotations.ReadOnlyHint {
		return false
	}
	if tool.Annotations.DestructiveHint == nil {
		return true
	}
	return *tool.Annotations.DestructiveHint
}

func toolOpenWorld(tool *sdk.Tool) bool {
	if tool == nil || tool.Annotations == nil || tool.Annotations.OpenWorldHint == nil {
		return true
	}
	return *tool.Annotations.OpenWorldHint
}

func toolIdempotent(tool *sdk.Tool) bool {
	return tool != nil && tool.Annotations != nil && tool.Annotations.IdempotentHint
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
	out.Servers = append(out.Servers, emailServerSnapshot())
	out.Tools = append(out.Tools, emailToolSnapshots()...)
	for _, conn := range r.conns {
		if conn == nil {
			continue
		}
		out.Servers = append(out.Servers, conn.snapshot)
		out.Tools = append(out.Tools, conn.tools...)
		out.Prompts = append(out.Prompts, conn.prompts...)
		out.Resources = append(out.Resources, conn.resources...)
	}

	slices.SortFunc(out.Servers, func(a, b ServerSnapshot) int {
		return strings.Compare(a.Label+a.ID, b.Label+b.ID)
	})
	slices.SortFunc(out.Tools, func(a, b ToolSnapshot) int {
		return strings.Compare(a.ServerLabel+a.Name, b.ServerLabel+b.Name)
	})
	slices.SortFunc(out.Prompts, func(a, b PromptSnapshot) int {
		return strings.Compare(a.ServerLabel+a.Name, b.ServerLabel+b.Name)
	})
	slices.SortFunc(out.Resources, func(a, b ResourceSnapshot) int {
		return strings.Compare(a.ServerLabel+a.Name, b.ServerLabel+b.Name)
	})

	if len(out.Servers) == 0 {
		out.Status = "empty"
	}
	return out
}

func (r *runtime) handleSampling(
	ctx context.Context,
	req *sdk.CreateMessageWithToolsRequest,
) (*sdk.CreateMessageWithToolsResult, error) {
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

func configuredServers(configJSON string) []ServerConfig {
	return withHostedTodoist(parseConfig(configJSON), secrets.NewResolver())
}

func withHostedTodoist(cfgs []ServerConfig, resolver secrets.Resolver) []ServerConfig {
	if resolver == nil {
		return cfgs
	}
	token, ok := resolver.Lookup("TODOIST_API_TOKEN")
	if !ok || strings.TrimSpace(token) == "" || hasHostedTodoist(cfgs) {
		return cfgs
	}
	next := make([]ServerConfig, 0, len(cfgs)+1)
	next = append(next, cfgs...)
	next = append(next, ServerConfig{
		ID:          "todoist",
		Label:       "Todoist",
		URL:         hostedTodoistMCPURL,
		Enabled:     true,
		AutoConnect: true,
		BearerToken: strings.TrimSpace(token),
	})
	return next
}

func hasHostedTodoist(cfgs []ServerConfig) bool {
	for _, cfg := range cfgs {
		if strings.EqualFold(strings.TrimSpace(cfg.URL), hostedTodoistMCPURL) {
			return true
		}
	}
	return false
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

func contentAsMaps(content []sdk.Content) []map[string]any {
	out := make([]map[string]any, 0, len(content))
	for _, item := range content {
		if item == nil {
			continue
		}
		raw, err := json.Marshal(item)
		if err != nil {
			continue
		}
		var mapped map[string]any
		if err := json.Unmarshal(raw, &mapped); err != nil || len(mapped) == 0 {
			continue
		}
		out = append(out, mapped)
	}
	return out
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
	tokenHash := ""
	if strings.TrimSpace(cfg.BearerToken) != "" {
		sum := sha256.Sum256([]byte(cfg.BearerToken))
		tokenHash = fmt.Sprintf("%x", sum)
	}
	headers := cfg.Headers
	if headers == nil {
		headers = map[string]string{}
	}
	raw, _ := json.Marshal(map[string]any{
		"id":                cfg.ID,
		"label":             cfg.Label,
		"url":               cfg.URL,
		"enabled":           cfg.Enabled,
		"auto_connect":      cfg.AutoConnect,
		"bearer_token_hash": tokenHash,
		"headers":           headers,
	})
	sum := sha256.Sum256(raw)
	return fmt.Sprintf("%x", sum)
}

var snapshotCacheRootOverride string

func useSnapshotCacheRootForTest(root string) func() {
	prev := snapshotCacheRootOverride
	snapshotCacheRootOverride = root
	return func() {
		snapshotCacheRootOverride = prev
	}
}

func loadCachedServerSnapshot(cfg ServerConfig, hash string, now time.Time) (*serverConn, time.Duration, bool) {
	path, err := serverSnapshotCachePath(cfg, hash)
	if err != nil {
		return nil, 0, false
	}
	//nolint:gosec // path is built from the configured server ID and cache hash under the qs-go cache root.
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, 0, false
	}
	var cached cachedServerSnapshot
	if err := json.Unmarshal(raw, &cached); err != nil {
		return nil, 0, false
	}
	if cached.Version != remoteCatalogCacheVersion || cached.Hash != hash || cached.CachedAt.IsZero() {
		return nil, 0, false
	}
	age := max(now.Sub(cached.CachedAt), 0)
	if age >= remoteCatalogCacheHardExpiry {
		return nil, age, false
	}

	snapshot := cached.Snapshot
	snapshot.ID = firstNonEmpty(snapshot.ID, cfg.ID)
	snapshot.Label = firstNonEmpty(snapshot.Label, serverLabel(cfg))
	snapshot.URL = firstNonEmpty(snapshot.URL, cfg.URL)
	snapshot.Enabled = cfg.Enabled
	snapshot.Connected = false
	snapshot.Status = "cached"
	snapshot.ToolCount = len(cached.Tools)
	snapshot.PromptCount = len(cached.Prompts)
	snapshot.ResourceCount = len(cached.Resources)

	return &serverConn{
		cfg:       cfg,
		hash:      hash,
		snapshot:  snapshot,
		tools:     cached.Tools,
		prompts:   cached.Prompts,
		resources: cached.Resources,
		cachedAt:  cached.CachedAt,
	}, age, true
}

func saveCachedServerSnapshot(cfg ServerConfig, hash string, conn *serverConn, cachedAt time.Time) error {
	if conn == nil {
		return nil
	}
	path, err := serverSnapshotCachePath(cfg, hash)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	snapshot := conn.snapshot
	snapshot.Status = "connected"
	snapshot.Connected = true
	snapshot.ToolCount = len(conn.tools)
	snapshot.PromptCount = len(conn.prompts)
	snapshot.ResourceCount = len(conn.resources)
	data, err := json.MarshalIndent(cachedServerSnapshot{
		Version:   remoteCatalogCacheVersion,
		Hash:      hash,
		CachedAt:  cachedAt,
		Snapshot:  snapshot,
		Tools:     conn.tools,
		Prompts:   conn.prompts,
		Resources: conn.resources,
	}, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o600)
}

func serverSnapshotCachePath(cfg ServerConfig, hash string) (string, error) {
	root := strings.TrimSpace(snapshotCacheRootOverride)
	if root == "" {
		cacheRoot, err := os.UserCacheDir()
		if err != nil {
			return "", err
		}
		root = filepath.Join(cacheRoot, "quickshell", "leftpanel", "mcp", "servers")
	}
	return filepath.Join(root, safeCacheName(cfg.ID)+"-"+hash+".json"), nil
}

func safeCacheName(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return "server"
	}
	return strings.Map(func(r rune) rune {
		if r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '-' || r == '_' || r == '.' {
			return r
		}
		return '_'
	}, value)
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
			Description: "Run a bubblewrap sandbox command. Inside the sandbox, " +
				"$HOME and /workspace are the same writable directory; " +
				"~/.cache and ~/.local are also writable, and other host paths " +
				"are read-only or unavailable.",
			Destructive: true,
			OpenWorld:   true,
			Risk:        "destructive",
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
						"type": "boolean",
						"description": "Whether to run the shell with login shell semantics. " +
							"Accepted for Codex compatibility; leftpanel currently always " +
							"runs bash -lc inside the sandbox.",
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
			Description: "Edit files in the sandbox using the Codex apply_patch format. " +
				"File paths must be relative to $HOME / /workspace.",
			Destructive: true,
			Risk:        "destructive",
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
	case "shell_command":
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
	case "shell_command", "apply_patch":
		return true
	default:
		return false
	}
}

func isLocalToolServer(serverID string) bool {
	switch strings.TrimSpace(serverID) {
	case "builtin":
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
	//nolint:gosec // shell sandbox files are intentionally user-visible workspace files.
	if err := os.MkdirAll(sandboxRoot, 0o755); err != nil {
		return shellError(toolName, err.Error())
	}
	hostHome, err := os.UserHomeDir()
	if err != nil {
		return shellError(toolName, err.Error())
	}
	//nolint:gosec // bwrap needs these normal user directories available inside the sandbox.
	if err := os.MkdirAll(filepath.Join(hostHome, ".cache"), 0o755); err != nil {
		return shellError(toolName, err.Error())
	}
	//nolint:gosec // bwrap needs these normal user directories available inside the sandbox.
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
	//nolint:gosec // command text is executed inside a constrained bwrap tool sandbox by design.
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
	//nolint:gosec // apply_patch writes normal user-visible files in the local sandbox.
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
			//nolint:gosec // apply_patch creates normal workspace directories, not secret storage.
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return nil, err
			}
			//nolint:gosec // apply_patch creates normal workspace files, not secrets.
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
			//nolint:gosec // target has already been validated to stay inside the sandbox and avoid symlink escapes.
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
			//nolint:gosec // apply_patch updates normal workspace directories, not secret storage.
			if err := os.MkdirAll(filepath.Dir(writeTarget), 0o755); err != nil {
				return nil, err
			}
			//nolint:gosec // apply_patch updates normal workspace files, not secrets.
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
	if suffix, ok := strings.CutPrefix(cwd, "/workspace"); ok {
		cwd = filepath.Join(home, suffix)
	}
	if !filepath.IsAbs(cwd) {
		cwd = filepath.Join(home, cwd)
	}
	clean := filepath.Clean(cwd)
	inHome := clean == home || strings.HasPrefix(clean, home+string(os.PathSeparator))
	inTmp := clean == "/tmp" || strings.HasPrefix(clean, "/tmp/")
	if inHome || inTmp {
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

func toolNamespace(serverID string) string {
	return "mcp__" + strings.TrimSpace(serverID) + "__"
}

func splitQualifiedToolName(serverID string, toolName string) (string, string) {
	cleanServer := strings.TrimSpace(serverID)
	cleanTool := strings.TrimSpace(toolName)
	if serverFromNamespace := namespaceServerID(cleanServer); serverFromNamespace != "" {
		return serverFromNamespace, unqualifiedToolForServer(serverFromNamespace, cleanTool)
	}
	if cleanServer != "" {
		return cleanServer, cleanTool
	}
	parts := strings.SplitN(cleanTool, "__", 2)
	if len(parts) == 2 && parts[0] != "" && parts[1] != "" {
		return parts[0], parts[1]
	}
	return cleanServer, cleanTool
}

func namespaceServerID(namespace string) string {
	clean := strings.TrimSpace(namespace)
	if !strings.HasPrefix(clean, "mcp__") || !strings.HasSuffix(clean, "__") {
		return ""
	}
	return strings.TrimSpace(strings.TrimSuffix(strings.TrimPrefix(clean, "mcp__"), "__"))
}

func unqualifiedToolForServer(serverID string, toolName string) string {
	if child, ok := strings.CutPrefix(strings.TrimSpace(toolName), strings.TrimSpace(serverID)+"__"); ok {
		return strings.TrimSpace(child)
	}
	return strings.TrimSpace(toolName)
}
