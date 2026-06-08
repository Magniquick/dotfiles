package oai

import (
	"bufio"
	"bytes"
	"cmp"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"maps"
	"net/http"
	"slices"
	"strings"

	"qs-go/internal/ai/shared"
)

// BaseURL normalizes a configured provider base URL or returns the fallback.
func BaseURL(configured, fallback string) string {
	baseURL := strings.TrimSpace(configured)
	if baseURL == "" {
		baseURL = fallback
	}
	return strings.TrimSuffix(baseURL, "/")
}

// StreamResponses posts a streaming Responses API request and parses the SSE stream.
func StreamResponses(ctx context.Context, baseURL, apiKey string, payload map[string]any, onToken func(string)) (shared.StreamResult, error) {
	body, _ := json.Marshal(payload)
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimSuffix(baseURL, "/")+"/responses", bytes.NewReader(body))
	if err != nil {
		return shared.StreamResult{}, err
	}
	httpReq.Header.Set("Authorization", "Bearer "+strings.TrimSpace(apiKey))
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := (&http.Client{Timeout: 0}).Do(httpReq)
	if err != nil {
		return shared.StreamResult{}, err
	}
	defer func() {
		_ = resp.Body.Close()
	}()
	if resp.StatusCode != http.StatusOK {
		raw, _ := io.ReadAll(resp.Body)
		return shared.StreamResult{}, fmt.Errorf("HTTP %d: %s", resp.StatusCode, shared.ExtractErrorMessage(raw))
	}
	return ParseResponsesStream(resp.Body, onToken)
}

// BuildResponsesTools converts shared tool descriptors into Responses API tool payloads.
func BuildResponsesTools(tools []shared.ToolDescriptor, includeWebSearch bool) []map[string]any {
	out := make([]map[string]any, 0, len(tools)+1)
	if includeWebSearch {
		out = append(out, map[string]any{"type": "web_search_preview"})
	}
	namespaceGroups := map[string]*responsesNamespaceGroup{}
	namespaceOrder := []string{}
	hasDeferred := false
	for _, tool := range tools {
		if strings.TrimSpace(tool.Kind) == "freeform" {
			item := map[string]any{
				"type":        "custom",
				"name":        tool.Name,
				"description": tool.Description,
				"format":      tool.Format,
			}
			if tool.DeferLoading {
				item["defer_loading"] = true
				hasDeferred = true
			}
			out = append(out, item)
			continue
		}
		if namespace := strings.TrimSpace(tool.Namespace); namespace != "" {
			group := namespaceGroups[namespace]
			if group == nil {
				group = &responsesNamespaceGroup{
					name:        namespace,
					description: firstNonEmpty(tool.NamespaceDescription, "Tools in the "+namespace+" namespace."),
				}
				namespaceGroups[namespace] = group
				namespaceOrder = append(namespaceOrder, namespace)
			}
			if tool.DeferLoading {
				hasDeferred = true
			}
			group.tools = append(group.tools, responsesFunctionTool(tool, responsesChildToolName(tool)))
			continue
		}
		item := map[string]any{
			"type":        "function",
			"name":        tool.Name,
			"description": responsesToolDescription(tool),
			"parameters":  DefaultSchema(tool.InputSchema),
			"strict":      false,
		}
		if tool.DeferLoading {
			item["defer_loading"] = true
			hasDeferred = true
		}
		out = append(out, item)
	}
	if hasDeferred {
		out = append(out, map[string]any{"type": "tool_search"})
	}
	slices.Sort(namespaceOrder)
	for _, namespace := range namespaceOrder {
		group := namespaceGroups[namespace]
		slices.SortFunc(group.tools, func(a, b map[string]any) int {
			return cmp.Compare(fmt.Sprint(a["name"]), fmt.Sprint(b["name"]))
		})
		out = append(out, map[string]any{
			"type":        "namespace",
			"description": group.description,
			"name":        group.name,
			"tools":       group.tools,
		})
	}
	return out
}

type responsesNamespaceGroup struct {
	name        string
	description string
	tools       []map[string]any
}

func responsesFunctionTool(tool shared.ToolDescriptor, name string) map[string]any {
	item := map[string]any{
		"type":        "function",
		"description": responsesToolDescription(tool),
		"name":        name,
		"parameters":  DefaultSchema(tool.InputSchema),
		"strict":      false,
	}
	if tool.DeferLoading {
		item["defer_loading"] = true
	}
	return item
}

func responsesToolDescription(tool shared.ToolDescriptor) string {
	return strings.TrimSpace(tool.Description)
}

func responsesChildToolName(tool shared.ToolDescriptor) string {
	name := strings.TrimSpace(tool.Name)
	if serverID := strings.TrimSpace(tool.ServerID); serverID != "" {
		if child, ok := strings.CutPrefix(name, serverID+"__"); ok {
			return strings.TrimSpace(child)
		}
	}
	if namespaceServer := namespaceServerID(tool.Namespace); namespaceServer != "" {
		if child, ok := strings.CutPrefix(name, namespaceServer+"__"); ok {
			return strings.TrimSpace(child)
		}
	}
	return name
}

func namespaceServerID(namespace string) string {
	clean := strings.TrimSpace(namespace)
	if !strings.HasPrefix(clean, "mcp__") || !strings.HasSuffix(clean, "__") {
		return ""
	}
	return strings.TrimSpace(strings.TrimSuffix(strings.TrimPrefix(clean, "mcp__"), "__"))
}

// BuildResponsesInput converts chat history and the current user turn into Responses input items.
func BuildResponsesInput(history []shared.HistoryMessage, message string, attachments []shared.Attachment, backendLabel string) ([]map[string]any, error) {
	out := make([]map[string]any, 0, len(history)+1)
	for _, item := range history {
		if len(item.RawItems) > 0 {
			out = append(out, cloneRawItems(item.RawItems)...)
			continue
		}
		if item.ToolCall != nil {
			if len(item.ToolCall.RawItems) > 0 {
				out = append(out, cloneRawItems(item.ToolCall.RawItems)...)
				continue
			}
			if strings.TrimSpace(item.ToolCall.Input) != "" {
				out = append(out, map[string]any{
					"type":    "custom_tool_call",
					"call_id": item.ToolCall.ID,
					"name":    item.ToolCall.Name,
					"input":   item.ToolCall.Input,
				})
				continue
			}
			call := map[string]any{
				"type":      "function_call",
				"call_id":   item.ToolCall.ID,
				"name":      item.ToolCall.Name,
				"arguments": MustJSON(item.ToolCall.Arguments),
			}
			if namespace := strings.TrimSpace(item.ToolCall.Namespace); namespace != "" {
				call["namespace"] = namespace
			}
			out = append(out, call)
			continue
		}
		if item.ToolResult != nil {
			output := shared.ToolResultTranscriptOutput(*item.ToolResult)
			if item.ToolResult.Name == "apply_patch" {
				out = append(out, map[string]any{
					"type":    "custom_tool_call_output",
					"call_id": item.ToolResult.ToolCallID,
					"name":    item.ToolResult.Name,
					"output":  output,
				})
				continue
			}
			out = append(out, map[string]any{
				"type":    "function_call_output",
				"call_id": item.ToolResult.ToolCallID,
				"output":  output,
			})
			continue
		}
		role := "user"
		contentType := "input_text"
		if item.Sender == "assistant" {
			role = "assistant"
			contentType = "output_text"
		}
		parts, err := BuildResponsesContentParts(contentType, item.Body, item.Attachments, backendLabel)
		if err != nil {
			return nil, err
		}
		out = append(out, map[string]any{"role": role, "content": parts})
	}
	parts, err := BuildResponsesContentParts("input_text", message, attachments, backendLabel)
	if err != nil {
		return nil, err
	}
	out = append(out, map[string]any{"role": "user", "content": parts})
	return out, nil
}

// BuildResponsesContentParts converts message text and attachments into Responses content parts.
func BuildResponsesContentParts(textType string, text string, attachments []shared.Attachment, backendLabel string) ([]map[string]any, error) {
	parts := make([]map[string]any, 0, len(attachments)+1)
	for _, attachment := range attachments {
		if u := strings.TrimSpace(attachment.URL); u != "" {
			parts = append(parts, map[string]any{"type": "input_image", "image_url": u})
			continue
		}
		dataURI, ok, err := ImageDataURI(attachment, backendLabel)
		if err != nil {
			return nil, err
		}
		if ok {
			parts = append(parts, map[string]any{"type": "input_image", "image_url": dataURI})
		}
	}
	if strings.TrimSpace(text) != "" || len(parts) == 0 {
		parts = append(parts, map[string]any{"type": textType, "text": text})
	}
	return parts, nil
}

func cloneRawItems(items []map[string]any) []map[string]any {
	out := make([]map[string]any, 0, len(items))
	for _, item := range items {
		if len(item) == 0 {
			continue
		}
		next := make(map[string]any, len(item))
		maps.Copy(next, item)
		out = append(out, next)
	}
	return out
}

// ImageDataURI returns an image attachment as a data URI when the backend supports it.
func ImageDataURI(attachment shared.Attachment, backendLabel string) (string, bool, error) {
	bin, ok := shared.DecodeAttachmentBinary(attachment)
	if !ok {
		return "", false, nil
	}
	if !strings.HasPrefix(strings.ToLower(bin.MIME), "image/") {
		return "", false, fmt.Errorf("%s backend currently supports image attachments only", backendLabel)
	}
	return "data:" + bin.MIME + ";base64," + base64.StdEncoding.EncodeToString(bin.Data), true, nil
}

// DefaultSchema supplies the empty object schema required by Responses function tools.
func DefaultSchema(schema map[string]any) map[string]any {
	if len(schema) > 0 {
		return schema
	}
	return map[string]any{"type": "object", "properties": map[string]any{}}
}

// MustJSON serializes values for provider payloads that require JSON strings.
func MustJSON(value any) string {
	raw, _ := json.Marshal(value)
	return string(raw)
}

// ParseResponsesStream reads Responses SSE events into a shared stream result.
func ParseResponsesStream(r io.Reader, onToken func(string)) (shared.StreamResult, error) {
	reader := bufio.NewReader(r)
	var out shared.StreamResult
	var currentEvent string
	seenCalls := map[string]bool{}
	seenRaw := map[string]bool{}
	pendingRawItems := []map[string]any{}
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			if err == io.EOF {
				break
			}
			return out, err
		}
		line = strings.TrimSpace(line)
		if event, ok := strings.CutPrefix(line, "event:"); ok {
			currentEvent = strings.TrimSpace(event)
			continue
		}
		data, ok := strings.CutPrefix(line, "data:")
		if !ok {
			continue
		}
		data = strings.TrimSpace(data)
		if data == "" || data == "[DONE]" {
			continue
		}
		switch currentEvent {
		case "response.output_text.delta":
			var chunk struct {
				Delta string `json:"delta"`
			}
			if json.Unmarshal([]byte(data), &chunk) == nil && chunk.Delta != "" {
				onToken(chunk.Delta)
			}
		case "response.output_item.done":
			var chunk struct {
				Item map[string]any `json:"item"`
			}
			if json.Unmarshal([]byte(data), &chunk) == nil {
				appendResponseOutputItem(&out, seenCalls, seenRaw, &pendingRawItems, chunk.Item)
			}
		case "response.completed":
			var chunk struct {
				Response struct {
					Output []map[string]any `json:"output"`
					Usage  struct {
						InputTokens  int `json:"input_tokens"`
						OutputTokens int `json:"output_tokens"`
					} `json:"usage"`
				} `json:"response"`
			}
			if json.Unmarshal([]byte(data), &chunk) == nil {
				out.PromptTokens = chunk.Response.Usage.InputTokens
				out.OutputTokens = chunk.Response.Usage.OutputTokens
				for _, item := range chunk.Response.Output {
					appendResponseOutputItem(&out, seenCalls, seenRaw, &pendingRawItems, item)
				}
			}
		}
	}
	return out, nil
}

// NormalizeCompactOutput rewrites compacted local proxy output into replayable Responses items.
func NormalizeCompactOutput(input []map[string]any) []map[string]any {
	out := make([]map[string]any, len(input))
	for i, item := range input {
		next := make(map[string]any, len(item))
		maps.Copy(next, item)
		if next["type"] == "message" && next["role"] == "assistant" {
			if content, ok := next["content"].([]any); ok {
				for _, part := range content {
					if mapped, ok := part.(map[string]any); ok && mapped["type"] == "input_text" {
						mapped["type"] = "output_text"
					}
				}
			}
		}
		out[i] = next
	}
	return out
}

type responseOutputItem struct {
	ID        string `json:"id"`
	Type      string `json:"type"`
	CallID    string `json:"call_id"`
	Namespace string `json:"namespace"`
	Name      string `json:"name"`
	Arguments string `json:"arguments"`
	Input     string `json:"input"`
}

func appendResponseOutputItem(out *shared.StreamResult, seenCalls map[string]bool, seenRaw map[string]bool, pendingRawItems *[]map[string]any, raw map[string]any) {
	if len(raw) == 0 {
		return
	}
	itemType := strings.TrimSpace(fmt.Sprint(raw["type"]))
	if shouldPreserveRawOutputItem(itemType) {
		key := rawOutputItemKey(raw)
		if !seenRaw[key] {
			seenRaw[key] = true
			out.RawItems = append(out.RawItems, cloneRawItems([]map[string]any{raw})[0])
			if itemType == "tool_search_call" || itemType == "tool_search_output" {
				*pendingRawItems = append(*pendingRawItems, cloneRawItems([]map[string]any{raw})[0])
			}
		}
	}
	var item responseOutputItem
	if data, err := json.Marshal(raw); err == nil {
		_ = json.Unmarshal(data, &item)
	}
	appendToolCall(out, seenCalls, pendingRawItems, item, raw)
}

func shouldPreserveRawOutputItem(itemType string) bool {
	return strings.TrimSpace(itemType) != ""
}

func rawOutputItemKey(raw map[string]any) string {
	for _, key := range []string{"id", "call_id"} {
		value := strings.TrimSpace(fmt.Sprint(raw[key]))
		if value != "" && value != "<nil>" {
			return strings.TrimSpace(fmt.Sprint(raw["type"])) + ":" + value
		}
	}
	data, _ := json.Marshal(raw)
	return string(data)
}

func appendToolCall(out *shared.StreamResult, seen map[string]bool, pendingRawItems *[]map[string]any, item responseOutputItem, raw map[string]any) {
	if item.Type == "custom_tool_call" && strings.TrimSpace(item.Name) != "" {
		key := firstNonEmpty(item.CallID, item.Name)
		if seen[key] {
			return
		}
		seen[key] = true
		out.ToolCalls = append(out.ToolCalls, shared.ToolCall{
			ID:        item.CallID,
			Name:      item.Name,
			Arguments: map[string]any{"input": item.Input},
			Input:     item.Input,
			RawItems:  rawTraceForCall(pendingRawItems, raw),
		})
		return
	}
	if item.Type != "function_call" || strings.TrimSpace(item.Name) == "" {
		return
	}
	key := firstNonEmpty(item.CallID, item.Name)
	if seen[key] {
		return
	}
	seen[key] = true
	args := map[string]any{}
	if strings.TrimSpace(item.Arguments) != "" {
		_ = json.Unmarshal([]byte(item.Arguments), &args)
	}
	out.ToolCalls = append(out.ToolCalls, shared.ToolCall{
		ID:        item.CallID,
		Namespace: item.Namespace,
		Name:      item.Name,
		Arguments: args,
		RawItems:  rawTraceForCall(pendingRawItems, raw),
	})
}

func rawTraceForCall(pendingRawItems *[]map[string]any, raw map[string]any) []map[string]any {
	items := cloneRawItems(*pendingRawItems)
	if len(raw) > 0 {
		items = append(items, cloneRawItems([]map[string]any{raw})[0])
	}
	*pendingRawItems = nil
	return items
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}
