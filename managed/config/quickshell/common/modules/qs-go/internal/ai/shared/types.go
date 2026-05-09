package shared

// Attachment describes a user-provided file, data URI source, or remote URL.
type Attachment struct {
	Path string `json:"path,omitempty"`
	MIME string `json:"mime,omitempty"`
	B64  string `json:"b64,omitempty"`
	URL  string `json:"url,omitempty"`
}

// HistoryMessage is one replayable chat history item.
type HistoryMessage struct {
	Sender      string           `json:"sender"`
	Body        string           `json:"body"`
	Attachments []Attachment     `json:"attachments,omitempty"`
	ToolCall    *ToolCall        `json:"tool_call,omitempty"`
	ToolResult  *ToolResult      `json:"tool_result,omitempty"`
	RawItems    []map[string]any `json:"raw_items,omitempty"`
}

// ProviderConfig contains provider-specific connection settings.
type ProviderConfig struct {
	APIKey  string            `json:"api_key,omitempty"`
	BaseURL string            `json:"base_url,omitempty"`
	Extra   map[string]string `json:"extra,omitempty"`
}

// ModelCapabilities describes provider/model feature support.
type ModelCapabilities struct {
	SupportsImages     bool `json:"supports_images"`
	SupportsTools      bool `json:"supports_tools"`
	SupportsReasoning  bool `json:"supports_reasoning"`
	SupportsMultimodal bool `json:"supports_multimodal"`
	MaxInputTokens     int  `json:"max_input_tokens,omitempty"`
	MaxOutputTokens    int  `json:"max_output_tokens,omitempty"`
}

// ProviderMetadata is displayed for a registered provider.
type ProviderMetadata struct {
	ID          string
	Label       string
	Description string
}

// StreamRequest is the shared request sent to provider implementations.
type StreamRequest struct {
	ModelID      string
	RawModelID   string
	Provider     string
	Config       ProviderConfig
	SystemPrompt string
	History      []HistoryMessage
	Message      string
	Attachments  []Attachment
	Tools        []ToolDescriptor
}

// StreamResult contains streamed output metadata and tool calls.
type StreamResult struct {
	PromptTokens int
	OutputTokens int
	ToolCalls    []ToolCall
	RawItems     []map[string]any
	StopReason   string
}

// ToolDescriptor describes a tool exposed to model providers.
type ToolDescriptor struct {
	Name                 string         `json:"name"`
	Title                string         `json:"title,omitempty"`
	Description          string         `json:"description,omitempty"`
	InputSchema          map[string]any `json:"input_schema,omitempty"`
	Kind                 string         `json:"kind,omitempty"`
	Format               map[string]any `json:"format,omitempty"`
	ReadOnly             bool           `json:"read_only,omitempty"`
	Destructive          bool           `json:"destructive,omitempty"`
	OpenWorld            bool           `json:"open_world,omitempty"`
	Idempotent           bool           `json:"idempotent,omitempty"`
	Risk                 string         `json:"risk,omitempty"`
	ServerID             string         `json:"server_id,omitempty"`
	ServerLabel          string         `json:"server_label,omitempty"`
	Namespace            string         `json:"namespace,omitempty"`
	NamespaceDescription string         `json:"namespace_description,omitempty"`
	DeferLoading         bool           `json:"defer_loading,omitempty"`
	SearchText           string         `json:"search_text,omitempty"`
	FullInstructions     string         `json:"full_instructions,omitempty"`
}

// ToolCall is a parsed provider tool call.
type ToolCall struct {
	ID          string           `json:"id"`
	Namespace   string           `json:"namespace,omitempty"`
	Name        string           `json:"name"`
	Arguments   map[string]any   `json:"arguments,omitempty"`
	Input       string           `json:"input,omitempty"`
	RawItems    []map[string]any `json:"raw_items,omitempty"`
	ServerID    string           `json:"server_id,omitempty"`
	ServerLabel string           `json:"server_label,omitempty"`
	ToolTitle   string           `json:"tool_title,omitempty"`
	ReadOnly    bool             `json:"read_only,omitempty"`
	Destructive bool             `json:"destructive,omitempty"`
	OpenWorld   bool             `json:"open_world,omitempty"`
	Idempotent  bool             `json:"idempotent,omitempty"`
	Risk        string           `json:"risk,omitempty"`
}

// ToolResult is the canonical result for tool execution, UI display, and replay.
type ToolResult struct {
	ToolCallID        string           `json:"tool_call_id"`
	Name              string           `json:"name,omitempty"`
	Text              string           `json:"text,omitempty"`
	Data              map[string]any   `json:"data,omitempty"`
	Content           []map[string]any `json:"content,omitempty"`
	StructuredContent map[string]any   `json:"structured_content,omitempty"`
	Meta              map[string]any   `json:"meta,omitempty"`
	IsError           bool             `json:"is_error,omitempty"`
	DurationMS        int64            `json:"duration_ms,omitempty"`
}
