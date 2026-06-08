package mcp

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"
	"time"

	imap "github.com/emersion/go-imap/v2"
	"golang.org/x/oauth2"

	"qs-go/internal/appconfig"
	"qs-go/internal/googleauth"
	"qs-go/internal/secrets"
)

func TestEmailAccountsFromEnvSupportsMultipleAccountsAndGmailPreset(t *testing.T) {
	//nolint:gosec // test uses fake email passwords to exercise env parsing.
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
	withEmailConfig(t, map[string]string{"EMAIL_PERSONAL_PASSWORD": "gmail-app-password"}) //nolint:gosec // fake test password

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

func TestToolDescriptorsExposeEmailToolsInCodexNamespace(t *testing.T) {
	withEmailConfig(t, map[string]string{"EMAIL_PERSONAL_PASSWORD": "gmail-app-password"}) //nolint:gosec // fake test password

	tools, err := ToolDescriptors(`[]`)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	servers := map[string]string{}
	namespaces := map[string]string{}
	namespaceDescriptions := map[string]string{}
	fullInstructions := map[string]string{}
	readOnly := map[string]bool{}
	for _, tool := range tools {
		servers[tool.Name] = tool.ServerID
		namespaces[tool.Name] = tool.Namespace
		namespaceDescriptions[tool.Name] = tool.NamespaceDescription
		fullInstructions[tool.Name] = tool.FullInstructions
		readOnly[tool.Name] = tool.ReadOnly
	}
	for _, name := range []string{"email__email_accounts", "email__email_search", "email__email_read"} {
		if servers[name] != "email" {
			t.Fatalf("expected qualified %s descriptor on email server, got %#v", name, servers)
		}
		if namespaces[name] != "mcp__email__" {
			t.Fatalf("expected %s in email namespace, got %#v", name, namespaces)
		}
		if strings.Contains(namespaceDescriptions[name], "Email Accounts") {
			t.Fatalf("namespace description should stay short, got %q", namespaceDescriptions[name])
		}
		if !strings.Contains(fullInstructions[name], "Email Accounts") {
			t.Fatalf("expected full email instructions on descriptor, got %q", fullInstructions[name])
		}
		if !readOnly[name] {
			t.Fatalf("expected %s to be marked read-only", name)
		}
	}
	if servers["email__email_send"] != "" {
		t.Fatalf("email_send must not be advertised by default, got %#v", servers)
	}
}

func TestEmailToolSchemaEnumeratesConfiguredAccountIDs(t *testing.T) {
	withTwoEmailAccounts(t)

	var searchSchema map[string]any
	for _, tool := range emailToolSnapshots() {
		if tool.Name == "email_search" {
			searchSchema = tool.InputSchema
			break
		}
	}
	if searchSchema == nil {
		t.Fatalf("email_search schema missing")
	}
	properties := searchSchema["properties"].(map[string]any)
	account := properties["account"].(map[string]any)
	enum := account["enum"].([]any)
	if !containsAny(enum, "iit") || !containsAny(enum, "navon") || !containsAny(enum, nil) {
		t.Fatalf("account enum should expose configured ids plus null, got %#v", account)
	}
	description := account["description"].(string)
	if !strings.Contains(description, "iit = IIT Mail") || !strings.Contains(description, "navon = Personal Mail") {
		t.Fatalf("account description should map labels to ids, got %q", description)
	}
}

func TestSelectEmailAccountDefaultsToPersonalAccount(t *testing.T) {
	withTwoEmailAccounts(t)

	for _, args := range []map[string]any{
		nil,
		{},
		{"account": nil},
		{"account": ""},
		{"account": "default"},
		{"account": "null"},
	} {
		account, err := selectEmailAccount(args)
		if err != nil {
			t.Fatalf("select account for %#v: %v", args, err)
		}
		if account.ID != "navon" {
			t.Fatalf("default/null account should select navon for %#v, got %#v", args, account)
		}
	}
}

func TestSelectEmailAccountAcceptsPersonalAliases(t *testing.T) {
	withTwoEmailAccounts(t)

	for _, requested := range []string{"personal", "Personal Mail", "navonjohnlukose@gmail.com", "navon"} {
		account, err := selectEmailAccount(map[string]any{"account": requested})
		if err != nil {
			t.Fatalf("select account %q: %v", requested, err)
		}
		if account.ID != "navon" {
			t.Fatalf("expected %q to select navon, got %#v", requested, account)
		}
	}
}

func TestCallEmailAccountsDoesNotExposeSecrets(t *testing.T) {
	withEmailConfig(t, map[string]string{"EMAIL_PERSONAL_PASSWORD": "gmail-app-password"}) //nolint:gosec // fake test password

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
	withEmailConfig(t, map[string]string{"EMAIL_PERSONAL_PASSWORD": "gmail-app-password"}) //nolint:gosec // fake test password

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

func TestCallEmailSearchUsesGmailAPIRawQueryForGmailAccounts(t *testing.T) {
	withEmailConfig(t, map[string]string{"EMAIL_PERSONAL_PASSWORD": "gmail-app-password"}) //nolint:gosec // fake test password
	fake := &fakeGmailClient{
		listResult: gmailListResult{
			Messages: []gmailListedMessage{{ID: "gmail-msg-1", ThreadID: "thread-1"}},
			Estimate: 7,
		},
		messages: map[string]gmailMessage{
			"gmail-msg-1": {
				ID:        "gmail-msg-1",
				ThreadID:  "thread-1",
				Subject:   "Quarterly report",
				From:      "Alice <alice@example.com>",
				To:        "Me <me@gmail.com>",
				Date:      "2026-05-01T10:00:00Z",
				MessageID: "<rfc-message-id@example.com>",
				Snippet:   "Quarterly report snippet",
			},
		},
	}
	withGmailClientForTest(t, fake)

	rawQuery := `from:alice@example.com subject:"quarterly report" has:attachment`
	result, err := CallTool(`[]`, "", "email_search", map[string]any{
		"account": "personal",
		"query":   rawQuery,
		"limit":   3,
	})
	if err != nil {
		t.Fatalf("unexpected call error: %v", err)
	}
	if result.IsError {
		t.Fatalf("expected gmail search success, got %#v", result)
	}
	if fake.listQuery != rawQuery {
		t.Fatalf("gmail search should pass raw query to Gmail API, got %q", fake.listQuery)
	}
	if fake.listLimit != 3 {
		t.Fatalf("gmail search should pass capped limit to Gmail API, got %d", fake.listLimit)
	}
	if len(fake.getIDs) != 1 || fake.getIDs[0] != "gmail-msg-1" || fake.getIncludeBody[0] {
		t.Fatalf("gmail search should fetch listed message details without bodies, got ids=%#v includeBody=%#v", fake.getIDs, fake.getIncludeBody)
	}

	data := result.Data
	if data["matched_count"] != int64(7) || data["returned_count"] != 1 || data["limit"] != 3 {
		t.Fatalf("gmail result counts should preserve existing shape, got %#v", data)
	}
	messages := data["messages"].([]map[string]any)
	if len(messages) != 1 {
		t.Fatalf("expected one returned message, got %#v", messages)
	}
	message := messages[0]
	if _, ok := message["uid"]; ok {
		t.Fatalf("gmail search messages should not invent IMAP uid: %#v", message)
	}
	if message["id"] != "gmail-msg-1" || message["gmail_id"] != "gmail-msg-1" || message["thread_id"] != "thread-1" {
		t.Fatalf("gmail identity missing from search result: %#v", message)
	}
	if message["subject"] != "Quarterly report" || message["from"] != "Alice <alice@example.com>" || message["snippet"] != "Quarterly report snippet" {
		t.Fatalf("gmail details missing from search result: %#v", message)
	}
}

func TestCallEmailReadUsesGmailMessageIDForGmailAccounts(t *testing.T) {
	withEmailConfig(t, map[string]string{"EMAIL_PERSONAL_PASSWORD": "gmail-app-password"}) //nolint:gosec // fake test password
	fake := &fakeGmailClient{
		messages: map[string]gmailMessage{
			"gmail-msg-1": {
				ID:            "gmail-msg-1",
				ThreadID:      "thread-1",
				Subject:       "Quarterly report",
				From:          "Alice <alice@example.com>",
				To:            "Me <me@gmail.com>",
				Date:          "2026-05-01T10:00:00Z",
				MessageID:     "<rfc-message-id@example.com>",
				Snippet:       "Quarterly report snippet",
				BodyText:      "body text",
				BodyHTML:      "<p>body text</p>",
				BodyTruncated: true,
			},
		},
	}
	withGmailClientForTest(t, fake)

	result, err := CallTool(`[]`, "", "email_read", map[string]any{
		"account":        "personal",
		"id":             "gmail-msg-1",
		"max_body_chars": 4096,
	})
	if err != nil {
		t.Fatalf("unexpected call error: %v", err)
	}
	if result.IsError {
		t.Fatalf("expected gmail read success, got %#v", result)
	}
	if len(fake.getIDs) != 1 || fake.getIDs[0] != "gmail-msg-1" || !fake.getIncludeBody[0] || fake.getMaxBodyChars[0] != 4096 {
		t.Fatalf("gmail read should fetch by Gmail id with body, got ids=%#v includeBody=%#v max=%#v", fake.getIDs, fake.getIncludeBody, fake.getMaxBodyChars)
	}
	message := result.Data["message"].(map[string]any)
	if message["id"] != "gmail-msg-1" || message["body_text"] != "body text" || message["body_truncated"] != true {
		t.Fatalf("gmail read returned unexpected message payload: %#v", message)
	}
}

func TestGmailOAuthHTTPClientRefreshesExpiredTokenAndPersists(t *testing.T) {
	var tokenRequestBody string
	tokenServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Fatalf("refresh request method = %s, want POST", r.Method)
		}
		if err := r.ParseForm(); err != nil {
			t.Fatalf("parse refresh form: %v", err)
		}
		tokenRequestBody = r.Form.Encode()
		if r.Form.Get("grant_type") != "refresh_token" {
			t.Fatalf("grant_type = %q, want refresh_token", r.Form.Get("grant_type"))
		}
		if r.Form.Get("refresh_token") != "old-refresh" {
			t.Fatalf("refresh_token = %q, want old-refresh", r.Form.Get("refresh_token"))
		}
		clientID, clientSecret, ok := r.BasicAuth()
		if !ok || clientID != "gmail-client-id" || clientSecret != "gmail-client-secret" {
			t.Fatalf("refresh used wrong client credentials: basic=%v body=%s", ok, tokenRequestBody)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"access_token":"fresh-access","expires_in":3600,"token_type":"Bearer"}`))
	}))
	defer tokenServer.Close()
	restoreEndpoint := useGmailOAuthEndpointForTest(t, tokenServer.URL)
	defer restoreEndpoint()
	resourceServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer fresh-access" {
			t.Fatalf("resource request Authorization = %q, want Bearer fresh-access", r.Header.Get("Authorization"))
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	defer resourceServer.Close()

	store := secrets.NewMapStore(map[string]string{
		"GOOGLE_PERSONAL_TOKEN_JSON": mustOAuthTokenJSON(t, oauth2.Token{
			AccessToken:  "expired-access",
			RefreshToken: "old-refresh",
			TokenType:    "Bearer",
			Expiry:       time.Now().Add(-time.Hour),
		}),
		"GOOGLE_PERSONAL_CLIENT_ID":     "gmail-client-id",
		"GOOGLE_PERSONAL_CLIENT_SECRET": "gmail-client-secret",
	})
	cleanup := secrets.UseResolverForTest(store)
	defer cleanup()

	client, err := gmailOAuthHTTPClient(context.Background(), emailAccount{
		ID:       "personal",
		Provider: "gmail",
		Address:  "me@gmail.com",
		Google: googleauth.Account{
			ID:              "personal",
			Address:         "me@gmail.com",
			TokenJSON:       storeValue(t, store, "GOOGLE_PERSONAL_TOKEN_JSON"),
			ClientID:        storeValue(t, store, "GOOGLE_PERSONAL_CLIENT_ID"),
			ClientSecret:    storeValue(t, store, "GOOGLE_PERSONAL_CLIENT_SECRET"),
			TokenKey:        "GOOGLE_PERSONAL_TOKEN_JSON",
			ClientIDKey:     "GOOGLE_PERSONAL_CLIENT_ID",
			ClientSecretKey: "GOOGLE_PERSONAL_CLIENT_SECRET",
		},
	})
	if err != nil {
		t.Fatalf("gmailOAuthHTTPClient returned error: %v", err)
	}
	req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, resourceServer.URL, nil)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	resp, err := client.Transport.RoundTrip(req)
	if err != nil {
		t.Fatalf("authenticated resource request failed: %v", err)
	}
	if resp.Body != nil {
		_ = resp.Body.Close()
	}
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("resource status = %d, want %d", resp.StatusCode, http.StatusNoContent)
	}
	if tokenRequestBody == "" {
		t.Fatalf("refresh endpoint was not called")
	}
	stored := storeValue(t, store, "GOOGLE_PERSONAL_TOKEN_JSON")
	if !strings.Contains(stored, "fresh-access") || !strings.Contains(stored, "old-refresh") {
		t.Fatalf("refreshed token JSON was not persisted with preserved refresh token: %s", stored)
	}
}

func TestGmailOAuthHTTPClientRejectsNonRefreshableToken(t *testing.T) {
	_, err := gmailOAuthHTTPClient(context.Background(), emailAccount{
		ID:       "personal",
		Provider: "gmail",
		Address:  "me@gmail.com",
		Google: googleauth.Account{
			ID:      "personal",
			Address: "me@gmail.com",
			TokenJSON: mustOAuthTokenJSON(t, oauth2.Token{
				AccessToken: "access-only",
				TokenType:   "Bearer",
				Expiry:      time.Now().Add(time.Hour),
			}),
		},
	})
	if err == nil {
		t.Fatalf("expected access-token-only gmail config to be rejected")
	}
	if !strings.Contains(err.Error(), "refresh_token") {
		t.Fatalf("expected refresh_token error, got %v", err)
	}
}

func TestGmailOAuthHTTPClientRequiresClientCredentials(t *testing.T) {
	tokenJSON := mustOAuthTokenJSON(t, oauth2.Token{
		AccessToken:  "expired-access",
		RefreshToken: "old-refresh",
		TokenType:    "Bearer",
		Expiry:       time.Now().Add(-time.Hour),
	})
	_, err := gmailOAuthHTTPClient(context.Background(), emailAccount{
		ID:       "personal",
		Provider: "gmail",
		Address:  "me@gmail.com",
		Google: googleauth.Account{
			ID:        "personal",
			Address:   "me@gmail.com",
			TokenJSON: tokenJSON,
			TokenKey:  "GOOGLE_PERSONAL_TOKEN_JSON",
		},
	})
	if err == nil {
		t.Fatalf("expected missing client credential error")
	}
	if !strings.Contains(err.Error(), "GOOGLE_PERSONAL_CLIENT_ID") || !strings.Contains(err.Error(), "GOOGLE_PERSONAL_CLIENT_SECRET") {
		t.Fatalf("expected client credential keys in error, got %v", err)
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

func TestMailboxFromArgsForAccountMapsGmailAllAliases(t *testing.T) {
	account := emailAccount{ID: "navon", Provider: "gmail"}
	for _, mailbox := range []string{"ALL", "all", "All Mail", "all labels"} {
		if got := mailboxFromArgsForAccount(account, map[string]any{"mailbox": mailbox}); got != "[Gmail]/All Mail" {
			t.Fatalf("expected %q to map to Gmail All Mail, got %q", mailbox, got)
		}
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

func withTwoEmailAccounts(t *testing.T) {
	t.Helper()
	configCleanup := appconfig.UseConfigForTest(appconfig.Config{
		Email: appconfig.EmailConfig{Accounts: []appconfig.EmailAccountConfig{
			{
				ID:       "iit",
				Provider: "gmail",
				Label:    "IIT Mail",
				Address:  "24f2003934@ds.study.iitm.ac.in",
				Username: "24f2003934@ds.study.iitm.ac.in",
			},
			{
				ID:       "navon",
				Provider: "gmail",
				Label:    "Personal Mail",
				Address:  "navonjohnlukose@gmail.com",
				Username: "navonjohnlukose@gmail.com",
			},
		}},
	})
	t.Cleanup(configCleanup)
	withEmailSecrets(t, map[string]string{
		"EMAIL_IIT_PASSWORD":   "iit-password",
		"EMAIL_NAVON_PASSWORD": "navon-password",
	})
}

type fakeGmailClient struct {
	listQuery  string
	listLimit  int
	listResult gmailListResult

	getIDs          []string
	getIncludeBody  []bool
	getMaxBodyChars []int
	messages        map[string]gmailMessage
}

func (c *fakeGmailClient) listMessages(_ context.Context, query string, limit int) (gmailListResult, error) {
	c.listQuery = query
	c.listLimit = limit
	return c.listResult, nil
}

func (c *fakeGmailClient) getMessage(_ context.Context, id string, includeBody bool, maxBodyChars int) (gmailMessage, error) {
	c.getIDs = append(c.getIDs, id)
	c.getIncludeBody = append(c.getIncludeBody, includeBody)
	c.getMaxBodyChars = append(c.getMaxBodyChars, maxBodyChars)
	return c.messages[id], nil
}

func withGmailClientForTest(t *testing.T, client gmailClient) {
	t.Helper()
	original := newGmailClient
	newGmailClient = func(context.Context, emailAccount) (gmailClient, error) {
		return client, nil
	}
	t.Cleanup(func() {
		newGmailClient = original
	})
}

func containsAny(values []any, needle any) bool {
	return slices.Contains(values, needle)
}

func mustOAuthTokenJSON(t *testing.T, token oauth2.Token) string {
	t.Helper()
	raw, err := json.Marshal(token)
	if err != nil {
		t.Fatalf("marshal token: %v", err)
	}
	return string(raw)
}

func storeValue(t *testing.T, resolver secrets.Resolver, key string) string {
	t.Helper()
	value, ok := resolver.Lookup(key)
	if !ok {
		t.Fatalf("missing secret %s", key)
	}
	return value
}

func useGmailOAuthEndpointForTest(t *testing.T, tokenURL string) func() {
	t.Helper()
	previous := googleauth.Endpoint
	googleauth.Endpoint = oauth2.Endpoint{
		AuthURL:  previous.AuthURL,
		TokenURL: tokenURL,
	}
	return func() {
		googleauth.Endpoint = previous
	}
}
