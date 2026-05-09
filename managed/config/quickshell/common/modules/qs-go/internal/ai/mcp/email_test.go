package mcp

import (
	"encoding/json"
	"strings"
	"testing"

	imap "github.com/emersion/go-imap/v2"

	"qs-go/internal/appconfig"
	"qs-go/internal/secrets"
)

func TestEmailAccountsFromEnvSupportsMultipleAccountsAndGmailPreset(t *testing.T) {
	accounts, err := emailAccountsFromEnv(map[string]string{
		"EMAIL_ACCOUNTS":          "personal, work",
		"EMAIL_PERSONAL_PROVIDER": "gmail",
		"EMAIL_PERSONAL_ADDRESS":  "me@gmail.com",
		"EMAIL_PERSONAL_PASSWORD": "gmail-app-password",
		"EMAIL_WORK_PROVIDER":     "generic",
		"EMAIL_WORK_ADDRESS":      "me@example.net",
		"EMAIL_WORK_USERNAME":     "imap-user",
		"EMAIL_WORK_PASSWORD":     "generic-secret",
		"EMAIL_WORK_IMAP_HOST":    "imap.example.net",
		"EMAIL_WORK_IMAP_PORT":    "1993",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(accounts) != 2 {
		t.Fatalf("expected two accounts, got %#v", accounts)
	}

	personal := accounts[0]
	if personal.ID != "personal" || personal.Provider != "gmail" {
		t.Fatalf("unexpected gmail identity: %#v", personal)
	}
	if personal.IMAPHost != "imap.gmail.com" || personal.IMAPPort != 993 || personal.IMAPTLS != "ssl" {
		t.Fatalf("gmail IMAP preset not applied: %#v", personal)
	}
	if personal.Username != "me@gmail.com" || personal.From != "me@gmail.com" {
		t.Fatalf("gmail defaults not applied: %#v", personal)
	}

	work := accounts[1]
	if work.ID != "work" || work.Provider != "generic" {
		t.Fatalf("unexpected generic identity: %#v", work)
	}
	if work.IMAPHost != "imap.example.net" || work.IMAPPort != 1993 {
		t.Fatalf("generic overrides not applied: %#v", work)
	}
}

func TestRefreshIncludesEmailServerAndToolsWhenEnvConfigured(t *testing.T) {
	withEmailConfig(t, map[string]string{"EMAIL_PERSONAL_PASSWORD": "gmail-app-password"})

	var snapshot Snapshot
	if err := json.Unmarshal([]byte(Refresh(`[]`)), &snapshot); err != nil {
		t.Fatalf("refresh returned invalid json: %v", err)
	}

	var emailServer *ServerSnapshot
	for i := range snapshot.Servers {
		if snapshot.Servers[i].ID == "email" {
			emailServer = &snapshot.Servers[i]
			break
		}
	}
	if emailServer == nil {
		t.Fatalf("email server missing from snapshot: %#v", snapshot.Servers)
	}
	if !emailServer.Enabled || !emailServer.Connected || emailServer.Status != "connected" {
		t.Fatalf("email server should be connected when accounts exist: %#v", emailServer)
	}
	if emailServer.ToolCount != 3 {
		t.Fatalf("expected three email tools, got %#v", emailServer)
	}

	names := map[string]bool{}
	for _, tool := range snapshot.Tools {
		names[tool.QualifiedName] = true
	}
	for _, name := range []string{"email__email_accounts", "email__email_search", "email__email_read"} {
		if !names[name] {
			t.Fatalf("expected %s in snapshot, got %#v", name, names)
		}
	}
	if names["email__email_send"] {
		t.Fatalf("email_send must not be exposed by default: %#v", names)
	}
}

func TestToolDescriptorsExposeUnqualifiedEmailTools(t *testing.T) {
	withEmailConfig(t, map[string]string{"EMAIL_PERSONAL_PASSWORD": "gmail-app-password"})

	tools, err := ToolDescriptors(`[]`)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	servers := map[string]string{}
	readOnly := map[string]bool{}
	for _, tool := range tools {
		servers[tool.Name] = tool.ServerID
		readOnly[tool.Name] = tool.ReadOnly
	}
	for _, name := range []string{"email_accounts", "email_search", "email_read"} {
		if servers[name] != "email" {
			t.Fatalf("expected unqualified %s descriptor on email server, got %#v", name, servers)
		}
		if !readOnly[name] {
			t.Fatalf("expected %s to be marked read-only", name)
		}
	}
	if servers["email_send"] != "" {
		t.Fatalf("email_send must not be advertised by default, got %#v", servers)
	}
}

func TestCallEmailAccountsDoesNotExposeSecrets(t *testing.T) {
	withEmailConfig(t, map[string]string{"EMAIL_PERSONAL_PASSWORD": "gmail-app-password"})

	result, err := CallTool(`[]`, "", "email_accounts", map[string]any{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.IsError {
		t.Fatalf("expected success, got %#v", result)
	}
	raw, _ := json.Marshal(result)
	if strings.Contains(string(raw), "gmail-app-password") {
		t.Fatalf("email_accounts leaked secret: %s", raw)
	}
	if !strings.Contains(result.Text, "personal") || !strings.Contains(result.Text, "me@gmail.com") {
		t.Fatalf("account summary missing useful identity: %#v", result)
	}
}

func TestCallEmailSendIsDisabledByDefault(t *testing.T) {
	withEmailConfig(t, map[string]string{"EMAIL_PERSONAL_PASSWORD": "gmail-app-password"})

	result, err := CallTool(`[]`, "", "email_send", map[string]any{
		"to":        "you@example.net",
		"subject":   "nope",
		"body_text": "nope",
	})
	if err != nil {
		t.Fatalf("expected disabled tool result, got error: %v", err)
	}
	if !result.IsError || !strings.Contains(strings.ToLower(result.Text), "disabled") {
		t.Fatalf("expected disabled email_send error, got %#v", result)
	}
}

func TestSearchCriteriaFromArgsParsesGmailStyleQueryOperators(t *testing.T) {
	criteria, err := searchCriteriaFromArgs(map[string]any{
		"query": "from:alice@example.com to:bob@example.net subject:\"meeting notes\" after:2024/01/02 before:2024/02/03 is:unread has:attachment quarterly report",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	headers := map[string]string{}
	for _, header := range criteria.Header {
		headers[header.Key] = header.Value
	}
	if headers["From"] != "alice@example.com" || headers["To"] != "bob@example.net" || headers["Subject"] != "meeting notes" {
		t.Fatalf("gmail query headers not parsed: %#v", criteria.Header)
	}
	if criteria.Since.Format("2006-01-02") != "2024-01-02" {
		t.Fatalf("after: date not parsed: %v", criteria.Since)
	}
	if criteria.Before.Format("2006-01-02") != "2024-02-03" {
		t.Fatalf("before: date not parsed: %v", criteria.Before)
	}
	if len(criteria.NotFlag) != 1 || criteria.NotFlag[0] != "\\Seen" {
		t.Fatalf("is:unread not parsed: %#v", criteria.NotFlag)
	}
	if len(criteria.Text) != 1 || criteria.Text[0] != "quarterly report" {
		t.Fatalf("remaining query text not preserved: %#v", criteria.Text)
	}
	if len(criteria.Or) != 1 {
		t.Fatalf("has:attachment should add an attachment-oriented IMAP search OR, got %#v", criteria.Or)
	}
}

func TestSearchCriteriaExplicitArgsOverrideGmailStyleQueryOperators(t *testing.T) {
	criteria, err := searchCriteriaFromArgs(map[string]any{
		"query":       "from:alice@example.com subject:old is:unread",
		"from":        "carol@example.com",
		"subject":     "new",
		"unread_only": false,
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	headers := map[string]string{}
	for _, header := range criteria.Header {
		headers[header.Key] = header.Value
	}
	if headers["From"] != "carol@example.com" || headers["Subject"] != "new" {
		t.Fatalf("explicit args should override parsed query operators: %#v", criteria.Header)
	}
	if len(criteria.NotFlag) != 1 || criteria.NotFlag[0] != "\\Seen" {
		t.Fatalf("parsed unread should apply when explicit unread_only is absent/false: %#v", criteria.NotFlag)
	}
}

func TestMailboxFromArgsUsesGmailLabelWhenMailboxIsAbsent(t *testing.T) {
	if got := mailboxFromArgs(map[string]any{"query": "label:Work from:alice@example.com"}); got != "Work" {
		t.Fatalf("expected label to select mailbox, got %q", got)
	}
	if got := mailboxFromArgs(map[string]any{"mailbox": "INBOX", "query": "label:Work"}); got != "INBOX" {
		t.Fatalf("explicit mailbox should win, got %q", got)
	}
}

func TestLimitUIDsReportsMatchedCountBeforeCapping(t *testing.T) {
	uids := []imap.UID{5, 4, 3, 2, 1}
	limited, matched := limitUIDs(uids, 2)
	if matched != 5 {
		t.Fatalf("expected original match count, got %d", matched)
	}
	if len(limited) != 2 || limited[0] != 5 || limited[1] != 4 {
		t.Fatalf("unexpected limited UIDs: %#v", limited)
	}
}

func withEmailSecrets(t *testing.T, values map[string]string) {
	t.Helper()
	cleanup := secrets.UseResolverForTest(secrets.NewMapResolver(values))
	t.Cleanup(cleanup)
}

func withEmailConfig(t *testing.T, secretValues map[string]string) {
	t.Helper()
	configCleanup := appconfig.UseConfigForTest(appconfig.Config{
		Email: appconfig.EmailConfig{Accounts: []appconfig.EmailAccountConfig{
			{
				ID:       "personal",
				Provider: "gmail",
				Address:  "me@gmail.com",
			},
		}},
	})
	t.Cleanup(configCleanup)
	withEmailSecrets(t, secretValues)
}
