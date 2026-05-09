// Package main implements the qs-ai-cli helper command.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"qs-go/internal/ai"
	aimcp "qs-go/internal/ai/mcp"
	"qs-go/internal/ai/providers/oai"
	"qs-go/internal/ai/shared"
	"qs-go/internal/appconfig"
	"qs-go/internal/chatstore"
	"qs-go/internal/secrets"
)

const defaultPrompt = "You are a helpful, capable assistant for a sidebar chat interface. Be warm, clear, and efficient. Keep responses concise by default, using natural prose instead of heavy formatting unless structure is genuinely useful. Avoid filler, long preambles, and repetitive disclaimers. Answer the user's actual question first, make reasonable assumptions when ambiguity is minor, and ask at most one clarifying question when necessary. Be honest about uncertainty, avoid overstating confidence, and distinguish facts from suggestions. For practical tasks, focus on actionable guidance and concrete next steps. When explaining technical topics, be precise and readable rather than verbose. Maintain a calm and respectful tone."

type options struct {
	message              string
	model                string
	dbPath               string
	mcpConfigPath        string
	systemPrompt         string
	conversationID       string
	newConversation      bool
	temp                 bool
	dumpTools            bool
	dumpResponsesPayload bool
	dumpResponseItems    bool
}

type toolEvent struct {
	Kind           string            `json:"kind"`
	Phase          string            `json:"phase"`
	ToolCallID     string            `json:"tool_call_id"`
	ToolName       string            `json:"tool_name"`
	Status         string            `json:"status"`
	Summary        string            `json:"summary"`
	Subtitle       string            `json:"subtitle"`
	IsError        bool              `json:"is_error"`
	DetailSections json.RawMessage   `json:"detail_sections,omitempty"`
	ReplayItems    []json.RawMessage `json:"replay_items,omitempty"`
}

type presentationEvent struct {
	Kind string `json:"kind"`
}

type rawResponseItemsEvent struct {
	Kind  string            `json:"kind"`
	Items []json.RawMessage `json:"items"`
}

type activeToolRow struct {
	messageID string
	ordinal   int
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "qs-ai-cli:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	opts, err := parseOptions(args)
	if err != nil {
		return err
	}
	root := shellRoot()
	if root != "" {
		_ = os.Setenv("QS_SHELL_DIR", root)
	}
	if opts.model == "" {
		cfg, err := appconfig.Current()
		if err == nil {
			opts.model = strings.TrimSpace(cfg.Model.Default)
		}
	}
	if opts.model == "" {
		opts.model = "local/gpt-5.4-mini"
	}
	opts.model = canonicalModelID(opts.model)
	if opts.mcpConfigPath == "" {
		opts.mcpConfigPath = defaultMcpConfigPath(root)
	}
	if opts.systemPrompt == "" {
		opts.systemPrompt = loadDefaultPrompt(root)
	}
	mcpConfigJSON, err := readJSONFile(opts.mcpConfigPath, "[]")
	if err != nil {
		return err
	}
	if opts.dumpTools || opts.dumpResponsesPayload || opts.dumpResponseItems {
		log.SetOutput(io.Discard)
	}
	if opts.dumpTools {
		tools, err := aimcp.ToolDescriptors(mcpConfigJSON)
		if err != nil {
			return err
		}
		return writeJSON(map[string]any{
			"tools": oai.BuildResponsesTools(tools, true),
		})
	}
	if strings.TrimSpace(opts.message) == "" && !opts.dumpResponseItems {
		return fmt.Errorf("--message is required")
	}
	cleanupDB, err := prepareDatabasePath(&opts)
	if err != nil {
		return err
	}
	defer cleanupDB()

	store, err := chatstore.Open(opts.dbPath)
	if err != nil {
		return err
	}
	defer func() {
		_ = store.Close()
	}()

	providerID := providerFromModel(opts.model)
	openOpts := chatstore.OpenConversationOptions{
		ModelID:      opts.model,
		ProviderID:   providerID,
		SystemPrompt: opts.systemPrompt,
	}
	if opts.dumpResponseItems {
		conversationID := strings.TrimSpace(opts.conversationID)
		if conversationID == "" {
			active, ok, err := store.RestoreConversation(openOpts)
			if err != nil {
				return err
			}
			if !ok || strings.TrimSpace(active.ID) == "" {
				return fmt.Errorf("no active conversation to dump")
			}
			conversationID = active.ID
		}
		items, err := store.ListResponseItems(conversationID)
		if err != nil {
			return err
		}
		return writeJSON(map[string]any{
			"conversation_id": conversationID,
			"response_items":  items,
		})
	}
	var conv chatstore.Conversation
	var messages []chatstore.Message
	if opts.newConversation {
		conv, err = store.CreateConversation(openOpts)
	} else if strings.TrimSpace(opts.conversationID) != "" {
		currentID := ""
		if active, ok, activeErr := store.RestoreConversation(openOpts); activeErr != nil {
			return activeErr
		} else if ok {
			currentID = active.ID
		}
		var resumed []chatstore.Message
		conv, resumed, err = store.ResumeConversation(openOpts, currentID, opts.conversationID)
		messages = resumed
	} else {
		conv, err = store.OpenConversation(openOpts)
	}
	if err != nil {
		return err
	}
	if messages == nil {
		messages, err = store.ListMessages(conv.ID)
		if err != nil {
			return err
		}
	}
	responseItems, err := store.ListResponseItems(conv.ID)
	if err != nil {
		return err
	}
	history, err := historyFromMessagesAndResponseItems(messages, responseItems)
	if err != nil {
		return err
	}
	historyJSON := encodeJSON(history)
	if opts.dumpResponsesPayload {
		tools, err := aimcp.ToolDescriptors(mcpConfigJSON)
		if err != nil {
			return err
		}
		payload, err := buildResponsesPayload(rawModelID(opts.model), opts.systemPrompt, history, opts.message, nil, tools, true)
		if err != nil {
			return err
		}
		return writeJSON(payload)
	}

	nextOrdinal := len(messages)
	userOrdinal := nextOrdinal
	userID := newID()
	if err := store.UpsertMessage(chatstore.Message{
		ID:             userID,
		ConversationID: conv.ID,
		Ordinal:        nextOrdinal,
		Sender:         "user",
		Kind:           "chat",
		Status:         "complete",
		Body:           opts.message,
	}); err != nil {
		return err
	}
	nextOrdinal++

	fmt.Fprintf(os.Stderr, "conversation=%s model=%s db=%s\n", conv.ID, opts.model, opts.dbPath)
	providerConfigJSON, err := providerConfigJSON(secrets.NewResolver())
	if err != nil {
		return err
	}
	done := make(chan error, 1)
	var mu sync.Mutex
	assistantID := ""
	var assistant strings.Builder
	toolRows := map[string]activeToolRow{}
	nextReplayItemOrdinal := 0

	sessionID := ai.Stream(opts.model, providerConfigJSON, mcpConfigJSON, opts.systemPrompt, historyJSON, opts.message, "[]", func(token string, doneCode int) {
		switch doneCode {
		case 0:
			mu.Lock()
			assistant.WriteString(token)
			mu.Unlock()
			fmt.Print(token)
		case 1:
			mu.Lock()
			body := assistant.String()
			mu.Unlock()
			if strings.TrimSpace(body) != "" {
				if assistantID == "" {
					assistantID = newID()
				}
				done <- store.UpsertMessage(chatstore.Message{
					ID:             assistantID,
					ConversationID: conv.ID,
					Ordinal:        nextOrdinal,
					Sender:         "assistant",
					Kind:           "chat",
					Status:         "complete",
					Body:           body,
					CompletedAt:    timestamp(),
				})
				return
			}
			done <- nil
		case 2:
			kind := parsePresentationKind(token)
			if kind == "raw_response_items" {
				event, err := parseRawResponseItemsEvent(token)
				if err != nil {
					done <- err
					return
				}
				if err := persistResponseItems(store, conv.ID, userID, userOrdinal, &nextReplayItemOrdinal, "model_output", event.Items); err != nil {
					done <- err
					return
				}
				return
			}
			event, err := parseToolEvent(token)
			if err != nil {
				done <- err
				return
			}
			if err := persistToolEvent(store, conv.ID, &nextOrdinal, toolRows, event, token); err != nil {
				done <- err
				return
			}
			if err := persistResponseItems(store, conv.ID, userID, userOrdinal, &nextReplayItemOrdinal, "tool_output", event.ReplayItems); err != nil {
				done <- err
				return
			}
			fmt.Fprintf(os.Stderr, "\n[tool] %s %s %s\n", event.Phase, event.ToolName, event.Summary)
		case -1:
			done <- fmt.Errorf("%s", token)
		}
	})
	if sessionID == 0 {
		return fmt.Errorf("failed to start stream")
	}
	return <-done
}

func parseOptions(args []string) (options, error) {
	var opts options
	fs := flag.NewFlagSet("qs-ai-cli", flag.ContinueOnError)
	fs.StringVar(&opts.message, "message", "", "message to send")
	fs.StringVar(&opts.model, "model", "", "canonical model id, e.g. local/gpt-5.4-mini")
	fs.StringVar(&opts.dbPath, "db", "", "conversation sqlite path")
	fs.StringVar(&opts.mcpConfigPath, "mcp-config", "", "leftpanel MCP config JSON path")
	fs.StringVar(&opts.systemPrompt, "system-prompt", "", "system prompt override")
	fs.StringVar(&opts.conversationID, "conversation", "", "closed conversation id to resume")
	fs.BoolVar(&opts.newConversation, "new", false, "create a new active conversation")
	fs.BoolVar(&opts.temp, "temp", false, "use an isolated temporary sqlite database")
	fs.BoolVar(&opts.dumpTools, "dump-tools", false, "print the Responses tools payload and exit")
	fs.BoolVar(&opts.dumpResponsesPayload, "dump-responses-payload", false, "print the Responses request payload and exit")
	fs.BoolVar(&opts.dumpResponseItems, "dump-response-items", false, "print persisted Responses replay ledger rows and exit")
	if err := fs.Parse(args); err != nil {
		return opts, err
	}
	dumpCount := 0
	for _, enabled := range []bool{opts.dumpTools, opts.dumpResponsesPayload, opts.dumpResponseItems} {
		if enabled {
			dumpCount++
		}
	}
	if dumpCount > 1 {
		return opts, fmt.Errorf("--dump-tools, --dump-responses-payload, and --dump-response-items are mutually exclusive")
	}
	if opts.newConversation && strings.TrimSpace(opts.conversationID) != "" {
		return opts, fmt.Errorf("--new and --conversation are mutually exclusive")
	}
	if opts.temp && strings.TrimSpace(opts.dbPath) != "" {
		return opts, fmt.Errorf("--temp and --db are mutually exclusive")
	}
	if opts.temp && strings.TrimSpace(opts.conversationID) != "" {
		return opts, fmt.Errorf("--temp and --conversation are mutually exclusive")
	}
	if opts.message == "" && fs.NArg() > 0 {
		opts.message = strings.Join(fs.Args(), " ")
	}
	return opts, nil
}

func buildResponsesPayload(model string, systemPrompt string, history []shared.HistoryMessage, message string, attachments []shared.Attachment, tools []shared.ToolDescriptor, includeWebSearch bool) (map[string]any, error) {
	input, err := oai.BuildResponsesInput(history, message, attachments, "OpenAI")
	if err != nil {
		return nil, err
	}
	payload := map[string]any{
		"model":  strings.TrimSpace(model),
		"input":  input,
		"stream": true,
	}
	if strings.TrimSpace(systemPrompt) != "" {
		payload["instructions"] = systemPrompt
	}
	responsesTools := oai.BuildResponsesTools(tools, includeWebSearch)
	if len(responsesTools) > 0 {
		payload["tools"] = responsesTools
		payload["tool_choice"] = "auto"
	}
	return payload, nil
}

func prepareDatabasePath(opts *options) (func(), error) {
	if opts == nil {
		return func() {}, nil
	}
	if opts.temp {
		file, err := os.CreateTemp("", "qs-ai-cli-*.sqlite")
		if err != nil {
			return nil, err
		}
		path := file.Name()
		if err := file.Close(); err != nil {
			_ = os.Remove(path)
			return nil, err
		}
		opts.dbPath = path
		return func() {
			_ = os.Remove(path)
			_ = os.Remove(path + "-shm")
			_ = os.Remove(path + "-wal")
		}, nil
	}
	if opts.dbPath == "" {
		opts.dbPath = chatstore.DefaultPath()
	}
	return func() {}, nil
}

func canonicalModelID(raw string) string {
	model := strings.TrimSpace(raw)
	if model == "" {
		return "local/gpt-5.4-mini"
	}
	if strings.Contains(model, "/") {
		return model
	}
	if strings.HasPrefix(model, "gemini-") {
		return "gemini/" + model
	}
	if strings.HasPrefix(model, "gpt-5.") {
		return "local/" + model
	}
	return "openai/" + model
}

func providerConfigJSON(resolver secrets.Resolver) (string, error) {
	var values map[string]string
	if err := json.Unmarshal([]byte(appconfig.ResolveJSON(resolver)), &values); err != nil {
		return "", err
	}
	config := map[string]shared.ProviderConfig{
		"local": {
			APIKey:  values["LOCAL_API_KEY"],
			BaseURL: firstNonEmpty(values["LOCAL_BASE_URL"], "http://127.0.0.1:8317/v1"),
		},
		"openai": {
			APIKey:  values["OPENAI_API_KEY"],
			BaseURL: values["OPENAI_BASE_URL"],
		},
		"gemini": {
			APIKey: values["GEMINI_API_KEY"],
		},
	}
	return encodeJSON(config), nil
}

func historyFromMessagesAndResponseItems(messages []chatstore.Message, responseItems []chatstore.ResponseItem) ([]shared.HistoryMessage, error) {
	itemsByTurn, err := responseItemsByTurn(responseItems)
	if err != nil {
		return nil, err
	}
	history := make([]shared.HistoryMessage, 0, len(messages))
	consumedTurns := map[string]bool{}
	activeTurnHasLedger := false
	activeTurnHasRawMessage := false
	for _, msg := range messages {
		if msg.Status == "deleted" {
			continue
		}
		if msg.Kind == "chat" && msg.Sender == "user" {
			history = append(history, historyMessageFromChat(msg))
			if replay := itemsByTurn[msg.ID]; len(replay.rawItems) > 0 {
				history = append(history, shared.HistoryMessage{RawItems: replay.rawItems})
				consumedTurns[msg.ID] = true
				activeTurnHasLedger = true
				activeTurnHasRawMessage = replay.hasMessage
			} else {
				activeTurnHasLedger = false
				activeTurnHasRawMessage = false
			}
			continue
		}
		if replay := itemsByTurn[msg.ID]; len(replay.rawItems) > 0 {
			history = append(history, shared.HistoryMessage{RawItems: replay.rawItems})
			consumedTurns[msg.ID] = true
			activeTurnHasLedger = true
			activeTurnHasRawMessage = replay.hasMessage
			continue
		}
		if activeTurnHasLedger {
			if msg.Kind == "tool" {
				continue
			}
			if msg.Kind == "chat" && msg.Sender == "assistant" && activeTurnHasRawMessage {
				continue
			}
		}
		if msg.Kind != "chat" || strings.TrimSpace(msg.Body) == "" {
			continue
		}
		history = append(history, historyMessageFromChat(msg))
	}
	for _, item := range responseItems {
		if consumedTurns[item.TurnID] {
			continue
		}
		replay := itemsByTurn[item.TurnID]
		if len(replay.rawItems) == 0 {
			continue
		}
		history = append(history, shared.HistoryMessage{RawItems: replay.rawItems})
		consumedTurns[item.TurnID] = true
	}
	return history, nil
}

type turnReplayItems struct {
	rawItems   []map[string]any
	hasMessage bool
}

func responseItemsByTurn(items []chatstore.ResponseItem) (map[string]turnReplayItems, error) {
	out := map[string]turnReplayItems{}
	for _, item := range items {
		raw := map[string]any{}
		if err := json.Unmarshal([]byte(item.RawJSON), &raw); err != nil {
			return nil, err
		}
		replay := out[item.TurnID]
		replay.rawItems = append(replay.rawItems, raw)
		if strings.TrimSpace(fmt.Sprint(raw["type"])) == "message" {
			replay.hasMessage = true
		}
		out[item.TurnID] = replay
	}
	return out, nil
}

func historyMessageFromChat(msg chatstore.Message) shared.HistoryMessage {
	return shared.HistoryMessage{
		Sender:      msg.Sender,
		Body:        msg.Body,
		Attachments: attachmentsFromExtra(msg.ExtraJSON),
	}
}

func attachmentsFromExtra(raw string) []shared.Attachment {
	var extra struct {
		Attachments []shared.Attachment `json:"attachments"`
	}
	if err := json.Unmarshal([]byte(strings.TrimSpace(raw)), &extra); err != nil {
		return nil
	}
	return extra.Attachments
}

func rawModelID(model string) string {
	_, raw, ok := strings.Cut(strings.TrimSpace(model), "/")
	if !ok || strings.TrimSpace(raw) == "" {
		return strings.TrimSpace(model)
	}
	return strings.TrimSpace(raw)
}

func persistToolEvent(store *chatstore.Store, conversationID string, nextOrdinal *int, rows map[string]activeToolRow, event toolEvent, raw string) error {
	row, ok := rows[event.ToolCallID]
	if !ok {
		row = activeToolRow{messageID: firstNonEmpty(event.ToolCallID, newID()), ordinal: *nextOrdinal}
		rows[event.ToolCallID] = row
		*nextOrdinal = *nextOrdinal + 1
	}
	messageStatus := "complete"
	if event.Phase == "tool_start" {
		messageStatus = "streaming"
	}
	if event.IsError {
		messageStatus = "error"
	}
	if err := store.UpsertMessage(chatstore.Message{
		ID:             row.messageID,
		ConversationID: conversationID,
		Ordinal:        row.ordinal,
		Sender:         "tool",
		Kind:           "tool",
		Status:         messageStatus,
	}); err != nil {
		return err
	}
	return store.UpsertToolCall(chatstore.ToolCall{
		ID:          firstNonEmpty(event.ToolCallID, row.messageID),
		MessageID:   row.messageID,
		ToolCallID:  firstNonEmpty(event.ToolCallID, row.messageID),
		ToolName:    event.ToolName,
		Phase:       firstNonEmpty(event.Phase, "tool_start"),
		Status:      firstNonEmpty(event.Status, "running"),
		IsError:     event.IsError,
		Summary:     event.Summary,
		Subtitle:    event.Subtitle,
		PayloadJSON: raw,
		UpdatedAt:   timestamp(),
	})
}

func persistResponseItems(store *chatstore.Store, conversationID string, turnID string, turnOrdinal int, nextItemOrdinal *int, source string, rawItems []json.RawMessage) error {
	if len(rawItems) == 0 {
		return nil
	}
	items := make([]chatstore.ResponseItem, 0, len(rawItems))
	for _, raw := range rawItems {
		if !json.Valid(raw) {
			return fmt.Errorf("invalid response item JSON: %s", string(raw))
		}
		items = append(items, chatstore.ResponseItem{
			ItemOrdinal: *nextItemOrdinal,
			Source:      source,
			RawJSON:     string(raw),
		})
		*nextItemOrdinal = *nextItemOrdinal + 1
	}
	return store.UpsertResponseItems(conversationID, turnID, turnOrdinal, items)
}

func parsePresentationKind(raw string) string {
	var event presentationEvent
	if err := json.Unmarshal([]byte(raw), &event); err != nil {
		return ""
	}
	return strings.TrimSpace(event.Kind)
}

func parseRawResponseItemsEvent(raw string) (rawResponseItemsEvent, error) {
	var event rawResponseItemsEvent
	if err := json.Unmarshal([]byte(raw), &event); err != nil {
		return event, err
	}
	return event, nil
}

func parseToolEvent(raw string) (toolEvent, error) {
	var event toolEvent
	if err := json.Unmarshal([]byte(raw), &event); err != nil {
		return event, err
	}
	return event, nil
}

func providerFromModel(model string) string {
	provider, _, ok := strings.Cut(strings.TrimSpace(model), "/")
	if !ok || strings.TrimSpace(provider) == "" {
		return "local"
	}
	return strings.TrimSpace(provider)
}

func defaultMcpConfigPath(root string) string {
	return filepath.Join(root, "leftpanel", "mcp_servers.json")
}

func shellRoot() string {
	for _, key := range []string{"QS_SHELL_DIR", "QUICKSHELL_SHELL_DIR"} {
		if root := strings.TrimSpace(os.Getenv(key)); root != "" {
			return root
		}
	}
	cwd, err := os.Getwd()
	if err != nil {
		return "."
	}
	for dir := cwd; dir != "" && dir != string(os.PathSeparator); dir = filepath.Dir(dir) {
		if _, err := os.Stat(filepath.Join(dir, "shell.qml")); err == nil {
			return dir
		}
		next := filepath.Dir(dir)
		if next == dir {
			break
		}
	}
	return cwd
}

func loadDefaultPrompt(root string) string {
	//nolint:gosec // root is the discovered local shell checkout; this only reads its leftpanel config.
	data, err := os.ReadFile(filepath.Join(root, "leftpanel", "config.json"))
	if err != nil {
		return defaultPrompt
	}
	var cfg struct {
		Moods []struct {
			Name   string `json:"name"`
			Prompt string `json:"prompt"`
		} `json:"moods"`
	}
	if err := json.Unmarshal(data, &cfg); err != nil {
		return defaultPrompt
	}
	for _, mood := range cfg.Moods {
		if strings.EqualFold(strings.TrimSpace(mood.Name), "default") && strings.TrimSpace(mood.Prompt) != "" {
			return strings.TrimSpace(mood.Prompt)
		}
	}
	if len(cfg.Moods) > 0 && strings.TrimSpace(cfg.Moods[0].Prompt) != "" {
		return strings.TrimSpace(cfg.Moods[0].Prompt)
	}
	return defaultPrompt
}

func readJSONFile(path string, fallback string) (string, error) {
	//nolint:gosec // CLI reads user-selected local JSON files.
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return fallback, nil
	}
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(string(data)) == "" {
		return fallback, nil
	}
	return string(data), nil
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func encodeJSON(value any) string {
	data, err := json.Marshal(value)
	if err != nil {
		return "[]"
	}
	return string(data)
}

func writeJSON(value any) error {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	_, err = fmt.Fprintln(os.Stdout, string(data))
	return err
}

func newID() string {
	return fmt.Sprintf("%d", time.Now().UnixNano())
}

func timestamp() string {
	return time.Now().UTC().Format("2006-01-02T15:04:05.000Z")
}
