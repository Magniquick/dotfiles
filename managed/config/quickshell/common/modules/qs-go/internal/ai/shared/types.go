package shared

type Attachment struct {
	Path string `json:"path,omitempty"`
	MIME string `json:"mime,omitempty"`
	B64  string `json:"b64,omitempty"`
	URL  string `json:"url,omitempty"`
}

type HistoryMessage struct {
	Sender      string       `json:"sender"`
	Body        string       `json:"body"`
	Attachments []Attachment `json:"attachments,omitempty"`
	ToolCall    *ToolCall    `json:"tool_call,omitempty"`
	ToolResult  *ToolResult  `json:"tool_result,omitempty"`
}

type ProviderConfig struct {
	APIKey  string            `json:"api_key,omitempty"`
	BaseURL string            `json:"base_url,omitempty"`
	Extra   map[string]string `json:"extra,omitempty"`
}

type ModelCapabilities struct {
	SupportsImages     bool `json:"supports_images"`
	SupportsTools      bool `json:"supports_tools"`
	SupportsReasoning  bool `json:"supports_reasoning"`
	SupportsMultimodal bool `json:"supports_multimodal"`
	MaxInputTokens     int  `json:"max_input_tokens,omitempty"`
	MaxOutputTokens    int  `json:"max_output_tokens,omitempty"`
}

type ModelDescriptor struct {
	ID           string            `json:"id"`
	RawID        string            `json:"raw_id"`
	Provider     string            `json:"provider"`
	Label        string            `json:"label"`
	Description  string            `json:"description,omitempty"`
	Recommended  bool              `json:"recommended"`
	Capabilities ModelCapabilities `json:"capabilities"`
}

type ProviderCatalog struct {
	ID                string            `json:"id"`
	Label             string            `json:"label"`
	Description       string            `json:"description,omitempty"`
	Enabled           bool              `json:"enabled"`
	RecommendedModels []ModelDescriptor `json:"recommended_models"`
	Models            []ModelDescriptor `json:"models"`
}

type CatalogPayload struct {
	Providers []ProviderCatalog `json:"providers"`
	Status    string            `json:"status"`
	Error     string            `json:"error,omitempty"`
}

type ProviderMetadata struct {
	ID               string
	Label            string
	Description      string
	RecommendedRawID []string
	FallbackModels   []ModelDescriptor
}

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

type StreamResult struct {
	PromptTokens int
	OutputTokens int
	ToolCalls    []ToolCall
	StopReason   string
}

type ToolDescriptor struct {
	Name        string         `json:"name"`
	Title       string         `json:"title,omitempty"`
	Description string         `json:"description,omitempty"`
	InputSchema map[string]any `json:"input_schema,omitempty"`
	ServerID    string         `json:"server_id,omitempty"`
	ServerLabel string         `json:"server_label,omitempty"`
}

type ToolCall struct {
	ID        string         `json:"id"`
	Name      string         `json:"name"`
	Arguments map[string]any `json:"arguments,omitempty"`
}

type ToolResult struct {
	ToolCallID string         `json:"tool_call_id"`
	Name       string         `json:"name,omitempty"`
	Text       string         `json:"text,omitempty"`
	Data       map[string]any `json:"data,omitempty"`
	IsError    bool           `json:"is_error,omitempty"`
}
