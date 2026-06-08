// Package mcp tests built-in MCP tool behavior.
package mcp

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"

	"qs-go/internal/secrets"
)

func TestMain(m *testing.M) {
	cleanup := secrets.UseResolverForTest(secrets.NewMapResolver(nil))
	code := m.Run()
	cleanup()
	os.Exit(code)
}

func TestRefreshIncludesBuiltinServerAndTools(t *testing.T) {
	var snapshot Snapshot
	if err := json.Unmarshal([]byte(Refresh(`[]`)), &snapshot); err != nil {
		t.Fatalf("refresh returned invalid json: %v", err)
	}

	foundServer := false
	for _, server := range snapshot.Servers {
		if server.ID == "builtin" {
			foundServer = true
			if !server.Enabled || !server.Connected {
				t.Fatalf("builtin server should be enabled and connected: %#v", server)
			}
			if server.ToolCount != 2 {
				t.Fatalf("builtin server should expose shell_command and apply_patch, got %d tools", server.ToolCount)
			}
		}
	}
	if !foundServer {
		t.Fatalf("builtin server missing from snapshot: %#v", snapshot.Servers)
	}

	names := map[string]bool{}
	for _, tool := range snapshot.Tools {
		names[tool.QualifiedName] = true
	}
	if !names["builtin__shell_command"] {
		t.Fatalf("expected shell_command in snapshot, got %#v", names)
	}
	if !names["builtin__apply_patch"] {
		t.Fatalf("expected apply_patch in snapshot, got %#v", names)
	}
	if names["builtin__date_time"] {
		t.Fatalf("date_time should not be exposed as a builtin MCP tool: %#v", names)
	}
}

func TestToolDescriptorsIncludesBuiltinsWithoutRemoteConfig(t *testing.T) {
	tools, err := ToolDescriptors(`[]`)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	names := map[string]bool{}
	for _, tool := range tools {
		names[tool.Name] = true
	}
	if !names["shell_command"] {
		t.Fatalf("expected shell_command descriptor, got %#v", names)
	}
	if !names["apply_patch"] {
		t.Fatalf("expected apply_patch descriptor, got %#v", names)
	}
	if names["builtin__shell_command"] {
		t.Fatalf("built-in shell tool should be exposed as shell_command(), got %#v", names)
	}
	if names["builtin__date_time"] {
		t.Fatalf("date_time should not be exposed as a builtin descriptor: %#v", names)
	}

	var shellSchema map[string]any
	for _, tool := range tools {
		if tool.Name == "shell_command" {
			shellSchema = tool.InputSchema
			break
		}
	}
	props, _ := shellSchema["properties"].(map[string]any)
	for _, compat := range []string{"login", "sandbox_permissions", "justification", "prefix_rule"} {
		if _, ok := props[compat]; !ok {
			t.Fatalf("shell_command schema should keep Codex compatibility field %q: %#v", compat, props)
		}
	}
}

func TestToolReadOnlyUsesMCPAnnotation(t *testing.T) {
	if !toolReadOnly(&sdk.Tool{Annotations: &sdk.ToolAnnotations{ReadOnlyHint: true}}) {
		t.Fatalf("expected readOnlyHint to mark tool read-only")
	}
	if toolReadOnly(&sdk.Tool{}) {
		t.Fatalf("missing readOnlyHint must not mark tool read-only")
	}
}

func TestToolAnnotationRiskHints(t *testing.T) {
	destructive := true
	openWorld := false
	tool := &sdk.Tool{Annotations: &sdk.ToolAnnotations{
		DestructiveHint: &destructive,
		OpenWorldHint:   &openWorld,
		IdempotentHint:  true,
	}}

	if !toolDestructive(tool) || toolOpenWorld(tool) || !toolIdempotent(tool) {
		t.Fatalf("expected destructive/idempotent/closed-world hints")
	}
	if riskForTool(false, true) != "destructive" || riskForTool(true, true) != "read" {
		t.Fatalf("unexpected risk mapping")
	}
}

func TestContentAsMapsPreservesMCPContentShape(t *testing.T) {
	content := contentAsMaps([]sdk.Content{&sdk.TextContent{Text: "hello"}})

	if len(content) != 1 || content[0]["type"] != "text" || content[0]["text"] != "hello" {
		t.Fatalf("expected MCP text content map, got %#v", content)
	}
}

func TestBuiltinApplyPatchAddsAndUpdatesSandboxFiles(t *testing.T) {
	sandboxRoot, err := shellSandboxRoot()
	if err != nil {
		t.Fatalf("sandbox root: %v", err)
	}
	fileName := fmt.Sprintf("patch-%d.txt", time.Now().UnixNano())
	realPath := filepath.Join(sandboxRoot, fileName)
	t.Cleanup(func() {
		_ = os.Remove(realPath)
	})

	addPatch := fmt.Sprintf(`*** Begin Patch
*** Add File: %s
+hello
+old
*** End Patch
`, fileName)
	add, err := CallTool(`[]`, "", "apply_patch", map[string]any{"input": addPatch})
	if err != nil {
		t.Fatalf("apply_patch add returned error: %v", err)
	}
	if add.IsError {
		t.Fatalf("apply_patch add should work: %#v", add)
	}
	//nolint:gosec // test reads the sandbox file path it just asked apply_patch to create.
	raw, err := os.ReadFile(realPath)
	if err != nil {
		t.Fatalf("expected patched file: %v", err)
	}
	if string(raw) != "hello\nold\n" {
		t.Fatalf("unexpected add content: %q", string(raw))
	}

	updatePatch := fmt.Sprintf(`*** Begin Patch
*** Update File: %s
@@
-old
+new
*** End Patch
`, fileName)
	update, err := CallTool(`[]`, "", "apply_patch", map[string]any{"input": updatePatch})
	if err != nil {
		t.Fatalf("apply_patch update returned error: %v", err)
	}
	if update.IsError {
		t.Fatalf("apply_patch update should work: %#v", update)
	}
	//nolint:gosec // test reads the sandbox file path it just asked apply_patch to update.
	raw, err = os.ReadFile(realPath)
	if err != nil {
		t.Fatalf("expected updated file: %v", err)
	}
	if string(raw) != "hello\nnew\n" {
		t.Fatalf("unexpected update content: %q", string(raw))
	}
}

func TestBuiltinApplyPatchRejectsAbsolutePaths(t *testing.T) {
	result, err := CallTool(`[]`, "", "apply_patch", map[string]any{"input": `*** Begin Patch
*** Add File: /tmp/nope
+bad
*** End Patch
`})
	if err != nil {
		t.Fatalf("apply_patch returned unexpected call error: %v", err)
	}
	if !result.IsError || !strings.Contains(result.Text, "relative") {
		t.Fatalf("absolute paths should be rejected, got %#v", result)
	}
}

func TestBuiltinApplyPatchRejectsSymlinkEscape(t *testing.T) {
	sandboxRoot, err := shellSandboxRoot()
	if err != nil {
		t.Fatalf("sandbox root: %v", err)
	}
	//nolint:gosec // test creates a normal temporary sandbox directory.
	if err := os.MkdirAll(sandboxRoot, 0o755); err != nil {
		t.Fatalf("mkdir sandbox: %v", err)
	}
	linkName := fmt.Sprintf("escape-%d", time.Now().UnixNano())
	linkPath := filepath.Join(sandboxRoot, linkName)
	if err := os.Symlink(os.TempDir(), linkPath); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}
	t.Cleanup(func() {
		_ = os.Remove(linkPath)
	})

	result, err := CallTool(`[]`, "", "apply_patch", map[string]any{"input": fmt.Sprintf(`*** Begin Patch
*** Add File: %s/nope.txt
+bad
*** End Patch
`, linkName)})
	if err != nil {
		t.Fatalf("apply_patch returned unexpected call error: %v", err)
	}
	if !result.IsError || !strings.Contains(result.Text, "symlink") {
		t.Fatalf("symlink escapes should be rejected, got %#v", result)
	}
}

func TestBuiltinShellExecUsesBubblewrapSandbox(t *testing.T) {
	result, err := CallTool(`[]`, "", "shell_command", map[string]any{"command": "printf hello"})
	if err != nil {
		t.Fatalf("unexpected error for safe command: %v", err)
	}
	if result.IsError {
		t.Fatalf("safe command should not be an error: %#v", result)
	}
	if strings.TrimSpace(result.Data["stdout"].(string)) != "hello" {
		t.Fatalf("unexpected stdout: %#v", result.Data["stdout"])
	}
	if result.Data["sandbox_home"] == "" || result.Data["workspace"] != "/workspace" {
		t.Fatalf("expected sandbox-facing paths in result: %#v", result.Data)
	}
	hasHeader := strings.HasPrefix(result.Text, "Exit code: 0\nWall time: ")
	hasOutput := strings.Contains(result.Text, "\nOutput:\nhello")
	if result.Name != "shell_command" || !hasHeader || !hasOutput {
		t.Fatalf("expected Codex shell_command output text, got %#v", result)
	}
	if result.Data["cwd"] == "" || result.Data["workdir"] == "" {
		t.Fatalf("expected Codex-compatible cwd/workdir aliases in result: %#v", result.Data)
	}
	if _, exists := result.Data["sandbox_root"]; exists {
		t.Fatalf("result should not expose host sandbox_root path: %#v", result.Data)
	}

	fileName := fmt.Sprintf("persist-%d.txt", time.Now().UnixNano())
	write, err := CallTool(`[]`, "", "shell_command", map[string]any{
		"command": fmt.Sprintf("echo persisted > %s", fileName),
	})
	if err != nil {
		t.Fatalf("write command returned error: %v", err)
	}
	if write.IsError {
		t.Fatalf("write command should work inside sandbox: %#v", write)
	}
	sandboxRoot, err := shellSandboxRoot()
	if err != nil {
		t.Fatalf("sandbox root: %v", err)
	}
	realPath := filepath.Join(sandboxRoot, fileName)
	t.Cleanup(func() {
		_ = os.Remove(realPath)
	})
	//nolint:gosec // test reads the real sandbox file created by apply_patch.
	raw, err := os.ReadFile(realPath)
	if err != nil {
		t.Fatalf("expected real sandbox file at %s: %v", realPath, err)
	}
	if strings.TrimSpace(string(raw)) != "persisted" {
		t.Fatalf("unexpected persisted file content: %q", string(raw))
	}
}

func TestBuiltinShellExecEnablesPythonAndJavascript(t *testing.T) {
	python, err := CallTool(`[]`, "", "builtin__shell_command", map[string]any{"command": `python3 -c "print(2 + 3)"`})
	if err != nil {
		t.Fatalf("python command returned error: %v", err)
	}
	if python.IsError || strings.TrimSpace(python.Data["stdout"].(string)) != "5" {
		t.Fatalf("python should be enabled, got %#v", python)
	}

	js, err := CallTool(`[]`, "", "builtin__shell_command", map[string]any{"command": `node -e "console.log(6 * 7)"`})
	if err != nil {
		t.Fatalf("javascript command returned error: %v", err)
	}
	if js.IsError || !strings.Contains(js.Data["stdout"].(string), "42") {
		t.Fatalf("javascript should be enabled, got %#v", js)
	}
}

func TestBuiltinShellExecEnablesNetworking(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("network-ok"))
	}))
	defer server.Close()

	result, err := CallTool(`[]`, "", "builtin__shell_command", map[string]any{"command": "curl -s " + server.URL})
	if err != nil {
		t.Fatalf("network command returned error: %v", err)
	}
	if result.IsError || !strings.Contains(result.Data["stdout"].(string), "network-ok") {
		t.Fatalf("networking should be enabled, got %#v", result)
	}
}
