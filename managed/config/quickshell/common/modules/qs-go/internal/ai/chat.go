// Package ai provides streaming AI chat and model catalog functionality.
package ai

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// TokenCallback is called for each streamed token.
// done == 0: token
// done == 1: success/done
// done == -1: error (token = error message)
type TokenCallback func(token string, done int)

// HistoryMessage is one turn in the conversation history.
type HistoryMessage struct {
	Sender      string       `json:"sender"` // "user" | "assistant"
	Body        string       `json:"body"`
	Attachments []Attachment `json:"attachments,omitempty"`
}

// Attachment is a single user-supplied attachment entry.
type Attachment struct {
	Path string `json:"path,omitempty"`
	MIME string `json:"mime,omitempty"`
	B64  string `json:"b64,omitempty"`
	URL  string `json:"url,omitempty"`
}

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
	modelID, openaiKey, geminiKey, baseURL, systemPrompt,
	historyJSON, message, attachmentsJSON string,
	cb TokenCallback,
) int32 {
	id := nextSessionID()
	ctx, cancel := context.WithCancel(context.Background())
	sessions.Store(id, &sessionEntry{cancel: cancel})

	go func() {
		defer sessions.Delete(id)
		defer cancel()

		prov := selectProvider(modelID)
		history := parseHistory(historyJSON)
		attachments := parseAttachments(attachmentsJSON)
		req := providerRequest{
			ModelID:      strings.TrimSpace(modelID),
			OpenAIKey:    strings.TrimSpace(openaiKey),
			GeminiKey:    strings.TrimSpace(geminiKey),
			BaseURL:      strings.TrimSpace(baseURL),
			SystemPrompt: systemPrompt,
			History:      history,
			Message:      message,
			Attachments:  attachments,
		}

		if len(attachments) > 0 {
			if err := ensureAttachmentCapability(ctx, prov, req); err != nil {
				msg := err.Error()
				cb(msg, -1)
				storeMetrics(SessionMetrics{Model: modelID, TTFMS: -1, Finished: false, Error: msg})
				return
			}
		}

		start := time.Now()
		var chunkCount int
		ttf := -1.0

		result, err := prov.Stream(ctx, req, func(tok string) {
			if tok == "" {
				return
			}
			if chunkCount == 0 {
				ttf = float64(time.Since(start).Microseconds()) / 1000.0
			}
			chunkCount++
			cb(tok, 0)
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

func ensureAttachmentCapability(ctx context.Context, prov provider, req providerRequest) error {
	_ = ctx
	cap, ok := getModelCapability(prov.Name(), req.ModelID)
	if !ok {
		return fmt.Errorf("No capability metadata for model '%s'", req.ModelID)
	}
	if cap.Attachments != AttachmentSupportSupported {
		return fmt.Errorf("Attachments are not supported by model '%s'", req.ModelID)
	}
	return nil
}

func selectProvider(modelID string) provider {
	if strings.HasPrefix(strings.ToLower(strings.TrimSpace(modelID)), "gemini") {
		return geminiProvider{}
	}
	return openAIProvider{}
}

func parseHistory(historyJSON string) []HistoryMessage {
	trimmed := strings.TrimSpace(historyJSON)
	if trimmed == "" || trimmed == "[]" || trimmed == "null" {
		return nil
	}
	var msgs []HistoryMessage
	if err := json.Unmarshal([]byte(trimmed), &msgs); err != nil {
		return nil
	}
	return msgs
}

func parseAttachments(attachmentsJSON string) []Attachment {
	trimmed := strings.TrimSpace(attachmentsJSON)
	if trimmed == "" || trimmed == "[]" || trimmed == "null" {
		return nil
	}
	var attachments []Attachment
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
