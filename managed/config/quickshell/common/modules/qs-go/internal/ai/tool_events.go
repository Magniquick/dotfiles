package ai

import (
	"encoding/json"
	"fmt"
	"path/filepath"
	"sort"
	"strings"

	"qs-go/internal/ai/shared"
)

type toolUIEvent struct {
	Kind           string              `json:"kind"`
	Phase          string              `json:"phase"`
	ToolCallID     string              `json:"tool_call_id"`
	ToolName       string              `json:"tool_name"`
	Status         string              `json:"status"`
	Summary        string              `json:"summary"`
	Subtitle       string              `json:"subtitle,omitempty"`
	Icon           string              `json:"icon,omitempty"`
	IsError        bool                `json:"is_error,omitempty"`
	DetailSections []toolDetailSection `json:"detail_sections,omitempty"`
	AgentPayload   string              `json:"agent_payload,omitempty"`
}

type toolDetailSection struct {
	Title   string `json:"title"`
	Content string `json:"content"`
	Kind    string `json:"kind,omitempty"`
}

func buildToolStartEvent(call shared.ToolCall) toolUIEvent {
	return toolUIEvent{
		Kind:       "tool",
		Phase:      "tool_start",
		ToolCallID: call.ID,
		ToolName:   call.Name,
		Status:     "running",
		Summary:    "running " + call.Name + "...",
		Subtitle:   toolStartSubtitle(call),
		Icon:       toolIcon(call.Name, false),
		AgentPayload: mustJSON([]map[string]any{
			codexToolCallItem(call),
		}),
	}
}

func buildToolDoneEvent(call shared.ToolCall, result shared.ToolResult) toolUIEvent {
	event := toolUIEvent{
		Kind:       "tool",
		Phase:      "tool_done",
		ToolCallID: firstNonEmpty(result.ToolCallID, call.ID),
		ToolName:   firstNonEmpty(result.Name, call.Name),
		Status:     "success",
		Icon:       toolIcon(call.Name, result.IsError),
		IsError:    result.IsError,
	}
	if result.IsError {
		event.Phase = "tool_error"
		event.Status = "error"
	}

	switch call.Name {
	case "shell_command", "builtin__shell_command", "shell_exec", "builtin__shell_exec":
		fillShellExecEvent(&event, call, result)
	case "apply_patch", "builtin__apply_patch":
		fillApplyPatchEvent(&event, call, result)
	default:
		fillGenericToolEvent(&event, call, result)
	}
	event.AgentPayload = mustJSON([]map[string]any{
		codexToolCallItem(call),
		codexToolOutputItem(call, result),
	})
	return event
}

func toolStartSubtitle(call shared.ToolCall) string {
	switch call.Name {
	case "shell_command", "builtin__shell_command", "shell_exec", "builtin__shell_exec":
		return firstNonEmpty(stringArg(call.Arguments, "command"), stringArg(call.Arguments, "cmd"))
	case "apply_patch", "builtin__apply_patch":
		stats := parseApplyPatchStats(firstNonEmpty(call.Input, stringArg(call.Arguments, "input")))
		if len(stats) == 1 {
			return stats[0].Path
		}
		if len(stats) > 1 {
			return fmt.Sprintf("%d files", len(stats))
		}
		return "applying patch"
	default:
		return ""
	}
}

func fillShellExecEvent(event *toolUIEvent, call shared.ToolCall, result shared.ToolResult) {
	command := firstNonEmpty(stringArg(call.Arguments, "command"), stringArg(call.Arguments, "cmd"))
	if command == "" {
		command = "shell command"
	}
	event.Summary = "ran " + command
	event.Subtitle = shellResultSubtitle(result)
	event.DetailSections = []toolDetailSection{
		{Title: "Stdout", Content: shellResultDetails(result), Kind: "code"},
	}
	if event.IsError && event.Subtitle == "" {
		event.Subtitle = firstNonEmpty(result.Text, "failed")
	}
}

func fillApplyPatchEvent(event *toolUIEvent, call shared.ToolCall, result shared.ToolResult) {
	input := firstNonEmpty(call.Input, stringArg(call.Arguments, "input"))
	stats := parseApplyPatchStats(input)
	event.Summary = patchSummary(stats, result)
	event.Subtitle = "apply_patch completed"
	if event.IsError {
		event.Subtitle = firstNonEmpty(result.Text, "failed")
	}

	sections := []toolDetailSection{}
	if len(stats) > 0 {
		sections = append(sections, toolDetailSection{Title: "Changed files", Content: patchStatsTable(stats), Kind: "code"})
	} else if files := changedFiles(result); len(files) > 0 {
		sections = append(sections, toolDetailSection{Title: "Changed files", Content: strings.Join(files, "\n"), Kind: "code"})
	}
	if diff := applyPatchAsUnifiedDiff(input); diff != "" {
		sections = append(sections, toolDetailSection{Title: "Diff", Content: excerpt(diff, 10000), Kind: "diff"})
	}
	if result.IsError && strings.TrimSpace(result.Text) != "" {
		sections = append(sections, toolDetailSection{Title: "Error", Content: result.Text, Kind: "code"})
	}
	event.DetailSections = sections
}

func fillGenericToolEvent(event *toolUIEvent, call shared.ToolCall, result shared.ToolResult) {
	if result.IsError {
		event.Summary = "failed " + call.Name
		event.Subtitle = firstNonEmpty(result.Text, "tool returned an error")
	} else {
		event.Summary = "called " + call.Name
		event.Subtitle = firstNonEmpty(result.Text, "completed")
	}
	sections := []toolDetailSection{}
	if len(call.Arguments) > 0 {
		sections = append(sections, toolDetailSection{Title: "Arguments", Content: mustJSON(call.Arguments), Kind: "json"})
	}
	if strings.TrimSpace(result.Text) != "" {
		sections = append(sections, toolDetailSection{Title: "Result", Content: result.Text, Kind: "text"})
	}
	if len(result.Data) > 0 {
		sections = append(sections, toolDetailSection{Title: "Data", Content: mustJSON(result.Data), Kind: "json"})
	}
	event.DetailSections = sections
}

func toolIcon(name string, isError bool) string {
	if isError {
		return "!"
	}
	switch name {
	case "shell_command", "builtin__shell_command", "shell_exec", "builtin__shell_exec":
		return "$"
	case "apply_patch", "builtin__apply_patch":
		return "±"
	default:
		return "•"
	}
}

func codexToolCallItem(call shared.ToolCall) map[string]any {
	if strings.TrimSpace(call.Input) != "" {
		return map[string]any{
			"type":    "custom_tool_call",
			"call_id": call.ID,
			"name":    call.Name,
			"input":   call.Input,
		}
	}
	return map[string]any{
		"type":      "function_call",
		"call_id":   call.ID,
		"name":      call.Name,
		"arguments": mustJSON(call.Arguments),
	}
}

func codexToolOutputItem(call shared.ToolCall, result shared.ToolResult) map[string]any {
	output := strings.TrimSpace(result.Text)
	if output == "" && len(result.Data) > 0 {
		output = mustJSON(result.Data)
	}
	if call.Name == "apply_patch" || result.Name == "apply_patch" {
		return map[string]any{
			"type":    "custom_tool_call_output",
			"call_id": firstNonEmpty(result.ToolCallID, call.ID),
			"name":    firstNonEmpty(result.Name, call.Name),
			"output":  output,
		}
	}
	return map[string]any{
		"type":    "function_call_output",
		"call_id": firstNonEmpty(result.ToolCallID, call.ID),
		"output":  output,
	}
}

func stringArg(args map[string]any, key string) string {
	if args == nil {
		return ""
	}
	raw, ok := args[key]
	if !ok || raw == nil {
		return ""
	}
	return strings.TrimSpace(fmt.Sprint(raw))
}

func shellResultSubtitle(result shared.ToolResult) string {
	data := result.Data
	if boolData(data, "timed_out") {
		return "timed out"
	}
	exitCode := intData(data, "exit_code", 0)
	stdout := strings.TrimSpace(stringData(data, "stdout"))
	stderr := strings.TrimSpace(stringData(data, "stderr"))
	parts := []string{fmt.Sprintf("exit %d", exitCode)}
	switch {
	case stdout == "" && stderr == "":
		parts = append(parts, "no stdout")
	case stderr != "":
		parts = append(parts, "stderr")
	case stdout != "":
		parts = append(parts, "stdout")
	}
	if boolData(data, "truncated") {
		parts = append(parts, "output truncated")
	}
	return strings.Join(parts, " · ")
}

func shellResultDetails(result shared.ToolResult) string {
	data := result.Data
	stdout := stringData(data, "stdout")
	if strings.TrimSpace(stdout) == "" && strings.TrimSpace(result.Text) != "" {
		stdout = result.Text
	}
	return outputOrEmpty(stdout)
}

func outputOrEmpty(value string) string {
	if strings.TrimSpace(value) == "" {
		return "(no output)"
	}
	return strings.TrimRight(value, "\n")
}

type patchFileStats struct {
	Path      string
	Additions int
	Deletions int
}

func parseApplyPatchStats(input string) []patchFileStats {
	lines := strings.Split(input, "\n")
	statsByPath := map[string]*patchFileStats{}
	current := ""
	for _, line := range lines {
		switch {
		case strings.HasPrefix(line, "*** Add File: "):
			current = cleanPatchPath(strings.TrimSpace(strings.TrimPrefix(line, "*** Add File: ")))
			ensurePatchStats(statsByPath, current)
		case strings.HasPrefix(line, "*** Update File: "):
			current = cleanPatchPath(strings.TrimSpace(strings.TrimPrefix(line, "*** Update File: ")))
			ensurePatchStats(statsByPath, current)
		case strings.HasPrefix(line, "*** Delete File: "):
			current = cleanPatchPath(strings.TrimSpace(strings.TrimPrefix(line, "*** Delete File: ")))
			ensurePatchStats(statsByPath, current)
		case strings.HasPrefix(line, "*** Move to: "):
			next := cleanPatchPath(strings.TrimSpace(strings.TrimPrefix(line, "*** Move to: ")))
			if current != "" {
				statsByPath[next] = statsByPath[current]
				statsByPath[next].Path = next
				delete(statsByPath, current)
			}
			current = next
		case strings.HasPrefix(line, "*** "):
			current = ""
		case current != "" && strings.HasPrefix(line, "+"):
			statsByPath[current].Additions++
		case current != "" && strings.HasPrefix(line, "-"):
			statsByPath[current].Deletions++
		}
	}
	stats := make([]patchFileStats, 0, len(statsByPath))
	for _, stat := range statsByPath {
		stats = append(stats, *stat)
	}
	sort.Slice(stats, func(i, j int) bool { return stats[i].Path < stats[j].Path })
	return stats
}

func ensurePatchStats(stats map[string]*patchFileStats, path string) {
	if path == "" {
		return
	}
	if _, ok := stats[path]; !ok {
		stats[path] = &patchFileStats{Path: path}
	}
}

func cleanPatchPath(path string) string {
	if path == "" {
		return ""
	}
	return filepath.ToSlash(filepath.Clean(path))
}

func patchSummary(stats []patchFileStats, result shared.ToolResult) string {
	added, deleted := patchTotals(stats)
	if len(stats) == 1 {
		return fmt.Sprintf("edited %s +%d -%d", stats[0].Path, added, deleted)
	}
	if len(stats) > 1 {
		return fmt.Sprintf("edited %d files +%d -%d", len(stats), added, deleted)
	}
	files := changedFiles(result)
	if len(files) == 1 {
		return "edited " + files[0]
	}
	if len(files) > 1 {
		return fmt.Sprintf("edited %d files", len(files))
	}
	return "ran apply_patch"
}

func patchTotals(stats []patchFileStats) (int, int) {
	added := 0
	deleted := 0
	for _, stat := range stats {
		added += stat.Additions
		deleted += stat.Deletions
	}
	return added, deleted
}

func patchStatsTable(stats []patchFileStats) string {
	lines := make([]string, 0, len(stats))
	for _, stat := range stats {
		lines = append(lines, fmt.Sprintf("%s   +%d -%d", stat.Path, stat.Additions, stat.Deletions))
	}
	return strings.Join(lines, "\n")
}

func applyPatchAsUnifiedDiff(input string) string {
	lines := strings.Split(input, "\n")
	var out []string
	current := ""
	seenFile := false

	startFile := func(path, mode string) {
		clean := cleanPatchPath(path)
		if clean == "" {
			current = ""
			return
		}
		if seenFile {
			out = append(out, "")
		}
		seenFile = true
		current = clean
		out = append(out, fmt.Sprintf("diff --git a/%s b/%s", clean, clean))
		switch mode {
		case "add":
			out = append(out, "new file", "--- /dev/null", "+++ b/"+clean)
		case "delete":
			out = append(out, "deleted file", "--- a/"+clean, "+++ /dev/null")
		default:
			out = append(out, "--- a/"+clean, "+++ b/"+clean)
		}
	}

	for _, line := range lines {
		switch {
		case strings.HasPrefix(line, "*** Add File: "):
			startFile(strings.TrimSpace(strings.TrimPrefix(line, "*** Add File: ")), "add")
		case strings.HasPrefix(line, "*** Update File: "):
			startFile(strings.TrimSpace(strings.TrimPrefix(line, "*** Update File: ")), "update")
		case strings.HasPrefix(line, "*** Delete File: "):
			startFile(strings.TrimSpace(strings.TrimPrefix(line, "*** Delete File: ")), "delete")
		case strings.HasPrefix(line, "*** Move to: "):
			next := cleanPatchPath(strings.TrimSpace(strings.TrimPrefix(line, "*** Move to: ")))
			if current != "" && next != "" {
				out = append(out, "rename to "+next)
				current = next
			}
		case strings.HasPrefix(line, "*** "):
			current = ""
		case current != "" && strings.HasPrefix(line, "@@"):
			out = append(out, line)
		case current != "" && (strings.HasPrefix(line, "+") ||
			strings.HasPrefix(line, "-") ||
			strings.HasPrefix(line, " ")):
			out = append(out, line)
		}
	}

	return strings.TrimSpace(strings.Join(out, "\n"))
}

func changedFiles(result shared.ToolResult) []string {
	raw, ok := result.Data["changed_files"]
	if !ok || raw == nil {
		return nil
	}
	files := []string{}
	switch value := raw.(type) {
	case []string:
		files = append(files, value...)
	case []any:
		for _, item := range value {
			files = append(files, fmt.Sprint(item))
		}
	default:
		files = append(files, fmt.Sprint(value))
	}
	sort.Strings(files)
	return files
}

func excerpt(value string, max int) string {
	if len(value) <= max {
		return value
	}
	return value[:max] + "\n..."
}

func stringData(data map[string]any, key string) string {
	if data == nil {
		return ""
	}
	raw, ok := data[key]
	if !ok || raw == nil {
		return ""
	}
	return fmt.Sprint(raw)
}

func intData(data map[string]any, key string, fallback int) int {
	if data == nil {
		return fallback
	}
	switch value := data[key].(type) {
	case int:
		return value
	case int64:
		return int(value)
	case float64:
		return int(value)
	case json.Number:
		n, err := value.Int64()
		if err == nil {
			return int(n)
		}
	}
	return fallback
}

func boolData(data map[string]any, key string) bool {
	if data == nil {
		return false
	}
	value, _ := data[key].(bool)
	return value
}

func mustJSON(value any) string {
	raw, err := json.Marshal(value)
	if err != nil {
		return ""
	}
	return string(raw)
}
