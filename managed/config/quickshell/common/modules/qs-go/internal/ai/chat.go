// Package ai provides streaming AI chat and model catalog functionality.
package ai

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"

	aimcp "qs-go/internal/ai/mcp"
	"qs-go/internal/ai/models/helpers"
	"qs-go/internal/ai/providers"
	"qs-go/internal/ai/shared"
)

// TokenCallback is called for each streamed token.
// done == 0: token
// done == 1: success/done
// done == -1: error (token = error message)
type TokenCallback func(token string, done int)

// SessionMetrics holds timing and token stats for the last completed stream.
type SessionMetrics struct {
	Model        string  `json:"model"`
	ChunkCount   int     `json:"chunk_count"`   // streamed chunks (proxy for output tokens during stream)
	PromptTokens int     `json:"prompt_tokens"` // from provider response (0 if unavailable)
	OutputTokens int     `json:"output_tokens"` // from provider response (0 if unavailable)
	TTFMS        float64 `json:"ttf_ms"`        // time-to-first-token, ms; -1 if no tokens
	TotalMS      float64 `json:"total_ms"`      // total stream wall time, ms
	Finished     bool    `json:"finished"`      // false = cancelled or error
	Error        string  `json:"error,omitempty"`
}

type sessionEntry struct {
	cancel context.CancelFunc
}

var (
	sessionIDCounter int32
	sessions         sync.Map // int32 → *sessionEntry

	lastMetricsMu sync.Mutex
	lastMetrics   SessionMetrics
)

func nextSessionID() int32 {
	return atomic.AddInt32(&sessionIDCounter, 1)
}

// LastMetricsJSON returns JSON for the most recently completed (or failed) stream.
func LastMetricsJSON() string {
	lastMetricsMu.Lock()
	m := lastMetrics
	lastMetricsMu.Unlock()
	b, _ := json.Marshal(m)
	return string(b)
}

// Stream starts an AI chat session and fires cb for each token.
// Returns a session ID that can be passed to Cancel.
func Stream(
	modelID, providerConfigJSON, mcpConfigJSON, systemPrompt,
	historyJSON, message, attachmentsJSON string,
	cb TokenCallback,
) int32 {
	id := nextSessionID()
	ctx, cancel := context.WithCancel(context.Background())
	sessions.Store(id, &sessionEntry{cancel: cancel})

	go func() {
		defer sessions.Delete(id)
		defer cancel()

		providerID, rawModelID, err := splitCanonicalModelID(modelID)
		if err != nil {
			msg := err.Error()
			cb(msg, -1)
			storeMetrics(SessionMetrics{Model: modelID, TTFMS: -1, Finished: false, Error: msg})
			return
		}
		prov, ok := providers.Get(providerID)
		if !ok {
			msg := "unknown provider: " + providerID
			cb(msg, -1)
			storeMetrics(SessionMetrics{Model: modelID, TTFMS: -1, Finished: false, Error: msg})
			return
		}

		config := parseProviderConfig(providerConfigJSON)
		history := parseHistory(historyJSON)
		attachments := parseAttachments(attachmentsJSON)

		if len(attachments) > 0 {
			if capabilityErr := ensureAttachmentCapability(strings.TrimSpace(modelID)); capabilityErr != nil {
				msg := capabilityErr.Error()
				cb(msg, -1)
				storeMetrics(SessionMetrics{Model: modelID, TTFMS: -1, Finished: false, Error: msg})
				return
			}
		}

		start := time.Now()
		var chunkCount int
		ttf := -1.0
		onToken := func(tok string) {
			if tok == "" {
				return
			}
			if chunkCount == 0 {
				ttf = float64(time.Since(start).Microseconds()) / 1000.0
			}
			chunkCount++
			cb(tok, 0)
		}

		baseReq := shared.StreamRequest{
			ModelID:      strings.TrimSpace(modelID),
			RawModelID:   rawModelID,
			Provider:     providerID,
			Config:       config[providerID],
			SystemPrompt: systemPrompt,
			History:      history,
			Message:      message,
			Attachments:  attachments,
		}

		samplingHandler := func(handlerCtx context.Context, req *mcp.CreateMessageWithToolsRequest) (*mcp.CreateMessageWithToolsResult, error) {
			return sampleMcpRequest(handlerCtx, prov, baseReq, req)
		}
		elicitationHandler := func(context.Context, *mcp.ElicitRequest) (*mcp.ElicitResult, error) {
			return &mcp.ElicitResult{
				Action: "decline",
				Content: map[string]any{
					"reason": "Left panel MCP elicitation UI is not implemented",
				},
			}, nil
		}

		var result shared.StreamResult
		err = aimcp.WithStreamHandlers(mcpConfigJSON, samplingHandler, elicitationHandler, func() error {
			var streamErr error
			result, streamErr = streamWithTools(ctx, prov, baseReq, mcpConfigJSON, onToken)
			return streamErr
		})
		totalMS := float64(time.Since(start).Microseconds()) / 1000.0

		if err != nil {
			if errors.Is(err, context.Canceled) {
				storeMetrics(SessionMetrics{
					Model:        modelID,
					ChunkCount:   chunkCount,
					PromptTokens: result.PromptTokens,
					OutputTokens: result.OutputTokens,
					TTFMS:        ttf,
					TotalMS:      totalMS,
					Finished:     false,
				})
				return
			}
			msg := err.Error()
			storeMetrics(SessionMetrics{
				Model:        modelID,
				ChunkCount:   chunkCount,
				PromptTokens: result.PromptTokens,
				OutputTokens: result.OutputTokens,
				TTFMS:        ttf,
				TotalMS:      totalMS,
				Finished:     false,
				Error:        msg,
			})
			cb(msg, -1)
			return
		}

		storeMetrics(SessionMetrics{
			Model:        modelID,
			ChunkCount:   chunkCount,
			PromptTokens: result.PromptTokens,
			OutputTokens: result.OutputTokens,
			TTFMS:        ttf,
			TotalMS:      totalMS,
			Finished:     true,
		})
		cb("", 1)
	}()

	return id
}

func streamWithTools(
	ctx context.Context,
	prov providers.Provider,
	baseReq shared.StreamRequest,
	mcpConfigJSON string,
	onToken func(string),
) (shared.StreamResult, error) {
	req := baseReq
	if caps, ok := helpers.Query(baseReq.ModelID); ok && caps.SupportsTools {
		tools, err := aimcp.ToolDescriptors(mcpConfigJSON)
		if err == nil {
			req.Tools = tools
		}
	}

	history := append([]shared.HistoryMessage(nil), req.History...)
	message := req.Message
	attachments := req.Attachments

	var combined shared.StreamResult
	for round := 0; round < 8; round++ {
		req.History = history
		req.Message = message
		req.Attachments = attachments

		result, err := prov.Stream(ctx, req, onToken)
		combined.PromptTokens = result.PromptTokens
		combined.OutputTokens += result.OutputTokens
		combined.StopReason = result.StopReason
		if err != nil {
			return combined, err
		}
		if len(result.ToolCalls) == 0 {
			return combined, nil
		}

		history = append(history, shared.HistoryMessage{
			Sender:      "user",
			Body:        message,
			Attachments: attachments,
		})
		message = ""
		attachments = nil

		for _, toolCall := range result.ToolCalls {
			history = append(history, shared.HistoryMessage{
				Sender:   "assistant",
				ToolCall: &toolCall,
			})
			toolResult, err := aimcp.CallTool(mcpConfigJSON, "", toolCall.Name, toolCall.Arguments)
			if err != nil {
				toolResult = shared.ToolResult{
					Name:       toolCall.Name,
					ToolCallID: toolCall.ID,
					Text:       err.Error(),
					IsError:    true,
				}
			}
			toolResult.ToolCallID = toolCall.ID
			history = append(history, shared.HistoryMessage{
				Sender:     "user",
				ToolResult: &toolResult,
			})
		}
	}

	return combined, fmt.Errorf("too many MCP tool rounds")
}

func sampleMcpRequest(
	ctx context.Context,
	prov providers.Provider,
	baseReq shared.StreamRequest,
	req *mcp.CreateMessageWithToolsRequest,
) (*mcp.CreateMessageWithToolsResult, error) {
	if req == nil || req.Params == nil {
		return nil, fmt.Errorf("missing MCP sampling request")
	}

	history, message, attachments := convertSamplingMessages(req.Params.Messages)
	tools := convertMcpTools(req.Params.Tools)
	streamReq := shared.StreamRequest{
		ModelID:      baseReq.ModelID,
		RawModelID:   baseReq.RawModelID,
		Provider:     baseReq.Provider,
		Config:       baseReq.Config,
		SystemPrompt: firstNonEmpty(req.Params.SystemPrompt, baseReq.SystemPrompt),
		History:      history,
		Message:      message,
		Attachments:  attachments,
		Tools:        tools,
	}

	var text strings.Builder
	result, err := prov.Stream(ctx, streamReq, func(tok string) {
		text.WriteString(tok)
	})
	if err != nil {
		return nil, err
	}

	content := make([]mcp.Content, 0, 1+len(result.ToolCalls))
	if strings.TrimSpace(text.String()) != "" {
		content = append(content, &mcp.TextContent{Text: text.String()})
	}
	for _, toolCall := range result.ToolCalls {
		content = append(content, &mcp.ToolUseContent{
			ID:    toolCall.ID,
			Name:  toolCall.Name,
			Input: toolCall.Arguments,
		})
	}

	stopReason := "endTurn"
	if len(result.ToolCalls) > 0 {
		stopReason = "toolUse"
	}
	return &mcp.CreateMessageWithToolsResult{
		Content:    content,
		Model:      baseReq.ModelID,
		Role:       "assistant",
		StopReason: stopReason,
	}, nil
}

func convertSamplingMessages(messages []*mcp.SamplingMessageV2) ([]shared.HistoryMessage, string, []shared.Attachment) {
	if len(messages) == 0 {
		return nil, "", nil
	}
	out := make([]shared.HistoryMessage, 0, len(messages))
	for i, msg := range messages {
		item := convertSamplingMessage(msg)
		if i == len(messages)-1 && item.Sender == "user" && item.ToolResult == nil {
			return out, item.Body, item.Attachments
		}
		out = append(out, item)
	}
	return out, "", nil
}

func convertSamplingMessage(msg *mcp.SamplingMessageV2) shared.HistoryMessage {
	item := shared.HistoryMessage{Sender: "user"}
	if msg == nil {
		return item
	}
	if string(msg.Role) == "assistant" {
		item.Sender = "assistant"
	}
	for _, block := range msg.Content {
		switch content := block.(type) {
		case *mcp.TextContent:
			item.Body += content.Text
		case *mcp.ImageContent:
			item.Attachments = append(item.Attachments, shared.Attachment{
				MIME: content.MIMEType,
				B64:  base64.StdEncoding.EncodeToString(content.Data),
			})
		case *mcp.ToolUseContent:
			item.ToolCall = &shared.ToolCall{
				ID:        content.ID,
				Name:      content.Name,
				Arguments: content.Input,
			}
		case *mcp.ToolResultContent:
			data := map[string]any{}
			if mapped, ok := content.StructuredContent.(map[string]any); ok {
				data = mapped
			}
			item.ToolResult = &shared.ToolResult{
				ToolCallID: content.ToolUseID,
				Text:       joinToolResultContent(content.Content),
				Data:       data,
				IsError:    content.IsError,
			}
		}
	}
	return item
}

func joinToolResultContent(content []mcp.Content) string {
	parts := make([]string, 0, len(content))
	for _, block := range content {
		if text, ok := block.(*mcp.TextContent); ok && strings.TrimSpace(text.Text) != "" {
			parts = append(parts, text.Text)
		}
	}
	return strings.Join(parts, "\n")
}

func convertMcpTools(tools []*mcp.Tool) []shared.ToolDescriptor {
	out := make([]shared.ToolDescriptor, 0, len(tools))
	for _, tool := range tools {
		if tool == nil {
			continue
		}
		out = append(out, shared.ToolDescriptor{
			Name:        strings.TrimSpace(tool.Name),
			Title:       strings.TrimSpace(tool.Title),
			Description: strings.TrimSpace(tool.Description),
			InputSchema: asMap(tool.InputSchema),
		})
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

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func ensureAttachmentCapability(modelID string) error {
	cap, ok := helpers.Query(modelID)
	if !ok {
		return fmt.Errorf("No capability metadata for model '%s'", modelID)
	}
	if !cap.SupportsImages {
		return fmt.Errorf("Attachments are not supported by model '%s'", modelID)
	}
	return nil
}

func parseHistory(historyJSON string) []shared.HistoryMessage {
	trimmed := strings.TrimSpace(historyJSON)
	if trimmed == "" || trimmed == "[]" || trimmed == "null" {
		return nil
	}
	var msgs []shared.HistoryMessage
	if err := json.Unmarshal([]byte(trimmed), &msgs); err != nil {
		return nil
	}
	return msgs
}

func parseAttachments(attachmentsJSON string) []shared.Attachment {
	trimmed := strings.TrimSpace(attachmentsJSON)
	if trimmed == "" || trimmed == "[]" || trimmed == "null" {
		return nil
	}
	var attachments []shared.Attachment
	if err := json.Unmarshal([]byte(trimmed), &attachments); err != nil {
		return nil
	}
	return attachments
}

func storeMetrics(m SessionMetrics) {
	lastMetricsMu.Lock()
	lastMetrics = m
	lastMetricsMu.Unlock()
}

// Cancel terminates an active stream session.
func Cancel(id int32) {
	if v, ok := sessions.Load(id); ok {
		v.(*sessionEntry).cancel()
	}
}
