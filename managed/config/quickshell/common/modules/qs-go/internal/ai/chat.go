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

	"github.com/tmc/langchaingo/llms"
	"github.com/tmc/langchaingo/llms/googleai"
	lcgopenai "github.com/tmc/langchaingo/llms/openai"
	"google.golang.org/api/googleapi"
)

// TokenCallback is called for each streamed token.
// done == 0: token
// done == 1: success/done
// done == -1: error (token = error message)
type TokenCallback func(token string, done int)

// HistoryMessage is one turn in the conversation history.
type HistoryMessage struct {
	Sender string `json:"sender"` // "user" | "assistant"
	Body   string `json:"body"`
}

// SessionMetrics holds timing and token stats for the last completed stream.
type SessionMetrics struct {
	Model          string  `json:"model"`
	ChunkCount     int     `json:"chunk_count"`     // streamed chunks (proxy for output tokens during stream)
	PromptTokens   int     `json:"prompt_tokens"`   // from provider response (0 if unavailable)
	OutputTokens   int     `json:"output_tokens"`   // from provider response (0 if unavailable)
	TTFMS          float64 `json:"ttf_ms"`          // time-to-first-token, ms; -1 if no tokens
	TotalMS        float64 `json:"total_ms"`        // total stream wall time, ms
	Finished       bool    `json:"finished"`        // false = cancelled or error
	Error          string  `json:"error,omitempty"`
}

// sessionEntry stores the cancel func for an active stream.
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
	historyJSON, message, _ string,
	cb TokenCallback,
) int32 {
	id := nextSessionID()
	ctx, cancel := context.WithCancel(context.Background())
	sessions.Store(id, &sessionEntry{cancel: cancel})

	go func() {
		defer sessions.Delete(id)
		defer cancel()

		var (
			model llms.Model
			err   error
		)
		if strings.HasPrefix(modelID, "gemini") {
			model, err = googleai.New(ctx,
				googleai.WithAPIKey(geminiKey),
				googleai.WithDefaultModel(modelID),
			)
		} else {
			opts := []lcgopenai.Option{
				lcgopenai.WithToken(openaiKey),
				lcgopenai.WithModel(modelID),
			}
			if baseURL != "" {
				opts = append(opts, lcgopenai.WithBaseURL(baseURL))
			}
			model, err = lcgopenai.New(opts...)
		}
		if err != nil {
			msg := richError(err)
			cb(msg, -1)
			storeMetrics(SessionMetrics{Model: modelID, TTFMS: -1, Finished: false, Error: msg})
			return
		}

		// Metrics tracking.
		start := time.Now()
		var (
			chunkCount int
			ttf        float64 = -1
		)

		msgs := buildMessages(systemPrompt, historyJSON, message)
		resp, err := model.GenerateContent(ctx, msgs,
			llms.WithStreamingFunc(func(_ context.Context, chunk []byte) error {
				if len(chunk) > 0 {
					if chunkCount == 0 {
						ttf = float64(time.Since(start).Microseconds()) / 1000.0
					}
					chunkCount++
					cb(string(chunk), 0)
				}
				return nil
			}),
		)

		totalMS := float64(time.Since(start).Microseconds()) / 1000.0

		// Extract real token counts from the provider's GenerationInfo.
		var promptTok, outputTok int
		if resp != nil && len(resp.Choices) > 0 {
			info := resp.Choices[0].GenerationInfo
			if v, ok := info["PromptTokens"].(int); ok {
				promptTok = v
			}
			if v, ok := info["CompletionTokens"].(int); ok {
				outputTok = v
			}
		}

		if err != nil {
			if errors.Is(err, context.Canceled) {
				storeMetrics(SessionMetrics{Model: modelID, ChunkCount: chunkCount, PromptTokens: promptTok, OutputTokens: outputTok, TTFMS: ttf, TotalMS: totalMS, Finished: false})
				return
			}
			msg := richError(err)
			storeMetrics(SessionMetrics{Model: modelID, ChunkCount: chunkCount, PromptTokens: promptTok, OutputTokens: outputTok, TTFMS: ttf, TotalMS: totalMS, Finished: false, Error: msg})
			cb(msg, -1)
		} else {
			storeMetrics(SessionMetrics{Model: modelID, ChunkCount: chunkCount, PromptTokens: promptTok, OutputTokens: outputTok, TTFMS: ttf, TotalMS: totalMS, Finished: true})
			cb("", 1)
		}
	}()

	return id
}

// richError builds a clean, human-readable error string from the chain.
func richError(err error) string {
	// Walk the chain looking for a googleapi.Error (has Body with full details).
	var gapiErr *googleapi.Error
	if errors.As(err, &gapiErr) {
		return formatGoogleAPIError(gapiErr)
	}

	// langchaingo wraps with llms.Error; recurse into cause for real details.
	var llmsErr *llms.Error
	if errors.As(err, &llmsErr) && llmsErr.Cause != nil {
		return richError(llmsErr.Cause)
	}

	return err.Error()
}

// formatGoogleAPIError parses the structured JSON body of a googleapi.Error
// and returns a clean summary: code + message + quota info + retry delay.
func formatGoogleAPIError(e *googleapi.Error) string {
	type violation struct {
		QuotaMetric     string            `json:"quotaMetric"`
		QuotaDimensions map[string]string `json:"quotaDimensions"`
		QuotaValue      string            `json:"quotaValue"`
	}
	type detail struct {
		Type       string      `json:"@type"`
		RetryDelay string      `json:"retryDelay"`
		Violations []violation `json:"violations"`
	}
	type errObj struct {
		Code    int      `json:"code"`
		Message string   `json:"message"`
		Status  string   `json:"status"`
		Details []detail `json:"details"`
	}
	type envelope struct {
		Error errObj `json:"error"`
	}

	var obj errObj
	if body := strings.TrimSpace(e.Body); body != "" {
		var env envelope
		if strings.HasPrefix(body, "[") {
			var arr []envelope
			if json.Unmarshal([]byte(body), &arr) == nil && len(arr) > 0 {
				env = arr[0]
			}
		} else {
			json.Unmarshal([]byte(body), &env) //nolint:errcheck
		}
		obj = env.Error
	}
	// Fall back to fields googleapi already parsed.
	if obj.Code == 0 {
		obj.Code = e.Code
	}
	if obj.Message == "" {
		obj.Message = e.Message
	}

	var retryDelay string
	var quotas []string
	for _, d := range obj.Details {
		if strings.HasSuffix(d.Type, "RetryInfo") {
			retryDelay = d.RetryDelay
		}
		if strings.HasSuffix(d.Type, "QuotaFailure") {
			for _, v := range d.Violations {
				metric := v.QuotaMetric
				if i := strings.LastIndex(metric, "/"); i >= 0 {
					metric = metric[i+1:]
				}
				q := metric
				if model := v.QuotaDimensions["model"]; model != "" {
					q += " (" + model + ")"
				}
				if v.QuotaValue != "" {
					q += ", limit " + v.QuotaValue
				}
				quotas = append(quotas, q)
			}
		}
	}

	status := obj.Status
	if status == "" {
		status = "ERROR"
	}
	out := fmt.Sprintf("%d %s: %s", obj.Code, status, cleanAPIMessage(obj.Message))
	for _, q := range quotas {
		out += "\nQuota: " + q
	}
	if retryDelay != "" {
		out += "\nRetry after: " + retryDelay
	}
	return out
}

// cleanAPIMessage removes URL-containing lines and lines that duplicate
// structured fields (quota bullets, retry delay) from an API error message.
func cleanAPIMessage(msg string) string {
	var kept []string
	for _, line := range strings.Split(msg, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.Contains(line, "https://") || strings.Contains(line, "http://") {
			continue
		}
		// Drop lines that are already surfaced as structured fields.
		lower := strings.ToLower(line)
		if strings.HasPrefix(lower, "* quota exceeded") ||
			strings.HasPrefix(lower, "please retry in") {
			continue
		}
		kept = append(kept, line)
	}
	if len(kept) == 0 {
		return msg
	}
	return strings.Join(kept, " ")
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

func buildMessages(systemPrompt, historyJSON, message string) []llms.MessageContent {
	var msgs []llms.MessageContent
	if systemPrompt != "" {
		msgs = append(msgs, llms.TextParts(llms.ChatMessageTypeSystem, systemPrompt))
	}
	for _, h := range parseHistory(historyJSON) {
		t := llms.ChatMessageTypeHuman
		if h.Sender == "assistant" {
			t = llms.ChatMessageTypeAI
		}
		msgs = append(msgs, llms.TextParts(t, h.Body))
	}
	msgs = append(msgs, llms.TextParts(llms.ChatMessageTypeHuman, message))
	return msgs
}

func parseHistory(historyJSON string) []HistoryMessage {
	if historyJSON == "" || historyJSON == "[]" || historyJSON == "null" {
		return nil
	}
	var msgs []HistoryMessage
	if err := json.Unmarshal([]byte(historyJSON), &msgs); err != nil {
		return nil
	}
	return msgs
}
