package mcp

import "testing"

func TestSplitQualifiedToolNameAcceptsCodexMCPNamespace(t *testing.T) {
	serverID, toolName := splitQualifiedToolName("mcp__todoist__", "find-tasks-by-date")

	if serverID != "todoist" || toolName != "find-tasks-by-date" {
		t.Fatalf("expected Codex namespace to resolve to Todoist server, got server=%q tool=%q", serverID, toolName)
	}
}

func TestToolNamespaceUsesCodexMCPShape(t *testing.T) {
	if got := toolNamespace("todoist"); got != "mcp__todoist__" {
		t.Fatalf("unexpected namespace: %q", got)
	}
}

func TestDescriptorsFromSnapshotKeepsNamespaceShortAndDefersLargeServers(t *testing.T) {
	tools, err := descriptorsFromSnapshot(Snapshot{
		Servers: []ServerSnapshot{{
			ID:           "todoist",
			Label:        "Todoist",
			ServerName:   "todoist-mcp",
			Instructions: "LONG initialize instructions with examples and policies.",
			ToolCount:    11,
		}},
		Tools: []ToolSnapshot{{
			ServerID:      "todoist",
			ServerLabel:   "Todoist",
			Name:          "find-tasks-by-date",
			QualifiedName: "todoist__find-tasks-by-date",
			Title:         "Find tasks by date",
			Description:   "Find Todoist tasks by due date.",
			ReadOnly:      true,
		}},
	})
	if err != nil {
		t.Fatalf("descriptorsFromSnapshot: %v", err)
	}
	if len(tools) != 1 {
		t.Fatalf("expected one descriptor, got %#v", tools)
	}
	tool := tools[0]
	if !tool.DeferLoading {
		t.Fatalf("large remote server tools should be deferred: %#v", tool)
	}
	if tool.Namespace != "mcp__todoist__" {
		t.Fatalf("expected Codex MCP namespace, got %#v", tool)
	}
	if tool.NamespaceDescription == "" || tool.NamespaceDescription == "LONG initialize instructions with examples and policies." {
		t.Fatalf("namespace description should be short and discriminative, got %q", tool.NamespaceDescription)
	}
	if tool.FullInstructions != "LONG initialize instructions with examples and policies." {
		t.Fatalf("expected full instructions stored separately, got %#v", tool)
	}
	if tool.SearchText == "" || tool.Title == "" {
		t.Fatalf("expected searchable/title metadata, got %#v", tool)
	}
	if !tool.ReadOnly || tool.Risk != "read" {
		t.Fatalf("expected read-only risk metadata, got %#v", tool)
	}
}

func TestDescriptorsFromSnapshotDefersRemoteNamespacesWhenWholeCatalogIsLarge(t *testing.T) {
	snapshot := Snapshot{
		Servers: []ServerSnapshot{
			{ID: "email", Label: "Email", ToolCount: 3},
			{ID: "calendar", Label: "Calendar", ToolCount: 8},
			{ID: "builtin", Label: "Built-in", ToolCount: 2},
		},
	}
	for _, name := range []string{"email_accounts", "email_search", "email_read"} {
		snapshot.Tools = append(snapshot.Tools, ToolSnapshot{
			ServerID:      "email",
			Name:          name,
			QualifiedName: "email__" + name,
			Description:   "Email tool.",
			ReadOnly:      true,
		})
	}
	for range 8 {
		name := "calendar_tool"
		snapshot.Tools = append(snapshot.Tools, ToolSnapshot{
			ServerID:      "calendar",
			Name:          name,
			QualifiedName: name,
			Description:   "Calendar tool.",
			ReadOnly:      true,
		})
	}
	snapshot.Tools = append(snapshot.Tools, ToolSnapshot{
		ServerID:      "builtin",
		Name:          "shell_command",
		QualifiedName: "builtin__shell_command",
		Description:   "Run shell.",
	})

	tools, err := descriptorsFromSnapshot(snapshot)
	if err != nil {
		t.Fatalf("descriptorsFromSnapshot: %v", err)
	}
	remoteDeferred := map[string]bool{}
	localDeferred := map[string]bool{}
	for _, tool := range tools {
		if tool.ServerID == "email" || tool.ServerID == "calendar" {
			remoteDeferred[tool.ServerID] = tool.DeferLoading
		}
		if tool.ServerID == "builtin" {
			localDeferred[tool.Name] = tool.DeferLoading
		}
	}
	if !remoteDeferred["email"] || !remoteDeferred["calendar"] {
		t.Fatalf("expected all remote namespace children deferred once catalog is large, got %#v", tools)
	}
	if localDeferred["shell_command"] {
		t.Fatalf("builtin/local tools must stay direct, got %#v", tools)
	}
}

func TestDescriptorsFromSnapshotKeepsSmallRemoteCatalogDirect(t *testing.T) {
	tools, err := descriptorsFromSnapshot(Snapshot{
		Servers: []ServerSnapshot{{ID: "email", Label: "Email", ToolCount: 3}},
		Tools: []ToolSnapshot{
			{ServerID: "email", Name: "email_accounts", QualifiedName: "email__email_accounts", Description: "List accounts.", ReadOnly: true},
			{ServerID: "email", Name: "email_search", QualifiedName: "email__email_search", Description: "Search.", ReadOnly: true},
			{ServerID: "email", Name: "email_read", QualifiedName: "email__email_read", Description: "Read.", ReadOnly: true},
		},
	})
	if err != nil {
		t.Fatalf("descriptorsFromSnapshot: %v", err)
	}
	for _, tool := range tools {
		if tool.ServerID == "email" && tool.DeferLoading {
			t.Fatalf("small remote catalog should stay direct, got %#v", tools)
		}
	}
}
