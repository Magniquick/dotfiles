package mcp

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"mime"
	"net"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"time"

	imap "github.com/emersion/go-imap/v2"
	"github.com/emersion/go-imap/v2/imapclient"
	"github.com/emersion/go-message/charset"
	emersionmail "github.com/emersion/go-message/mail"
	gmail "google.golang.org/api/gmail/v1"
	"google.golang.org/api/option"

	"qs-go/internal/ai/shared"
	"qs-go/internal/appconfig"
	"qs-go/internal/googleauth"
	"qs-go/internal/secrets"
)

const (
	emailServerID    = "email"
	emailServerLabel = "Email Accounts"
)

const emailServerInstructions = "Email Accounts provides read-only mailbox tools for configured email accounts. Gmail accounts use the Gmail API with refreshable OAuth credentials. Use these tools only when the user asks about email, inbox messages, unread mail, message subjects, or reading a specific email UID or Gmail message id. Do not use email tools for Todoist tasks, projects, reminders, or general task management."

type emailAccount struct {
	ID       string
	Label    string
	Provider string
	Address  string
	From     string
	Username string
	Password string
	IMAPHost string
	IMAPPort int
	IMAPTLS  string

	Google googleauth.Account
}

func emailServerSnapshot() ServerSnapshot {
	accounts, err := loadEmailAccounts()
	status := "needs_config"
	connected := false
	if len(accounts) > 0 && err == nil {
		status = "connected"
		connected = true
	} else if err != nil {
		status = "error"
	}
	return ServerSnapshot{
		ID:            emailServerID,
		Label:         emailServerLabel,
		URL:           "builtin://email",
		Enabled:       true,
		Connected:     connected,
		Status:        status,
		Error:         errorString(err),
		ServerName:    "leftpanel-email",
		ServerVersion: clientVersion,
		Instructions:  emailServerInstructions,
		ToolCount:     len(emailToolSnapshots()),
		Capabilities: map[string]any{
			"tools":    true,
			"accounts": len(accounts),
		},
	}
}

func emailToolSnapshots() []ToolSnapshot {
	return []ToolSnapshot{
		{
			ServerID:      emailServerID,
			ServerLabel:   emailServerLabel,
			Name:          "email_accounts",
			QualifiedName: "email__email_accounts",
			Title:         "Email accounts",
			Description:   "List configured email accounts from leftpanel/config.toml without exposing credentials.",
			InputSchema:   objectSchema(nil, nil),
			ReadOnly:      true,
			Risk:          "read",
		},
		{
			ServerID:      emailServerID,
			ServerLabel:   emailServerLabel,
			Name:          "email_search",
			QualifiedName: "email__email_search",
			Title:         "Search email",
			Description:   "Search an email account for messages by text, headers, unread state, and date. Gmail accounts pass Gmail-style query operators directly to the Gmail API.",
			InputSchema: objectSchema(map[string]any{
				"account":     emailAccountProp(),
				"mailbox":     stringProp("Mailbox name. Defaults to INBOX."),
				"query":       stringProp("Search text or Gmail-style query operators, for example from:alice@example.com subject:\"meeting notes\" after:2024/01/01 before:2024/02/01 is:unread label:Work has:attachment."),
				"from":        stringProp("Sender address or text to match."),
				"to":          stringProp("Recipient address or text to match."),
				"subject":     stringProp("Subject text to match."),
				"unread_only": boolProp("Only return unread messages."),
				"since":       stringProp("Only return messages since this date. Accepts YYYY-MM-DD or RFC3339."),
				"limit":       numberProp("Maximum messages to return, capped at 50. Defaults to 10."),
			}, nil),
			ReadOnly: true,
			Risk:     "read",
		},
		{
			ServerID:      emailServerID,
			ServerLabel:   emailServerLabel,
			Name:          "email_read",
			QualifiedName: "email__email_read",
			Title:         "Read email",
			Description:   "Read one message by IMAP UID, or by Gmail API id for Gmail accounts, and return headers plus a bounded text/html body excerpt.",
			InputSchema: objectSchema(map[string]any{
				"account":        emailAccountProp(),
				"mailbox":        stringProp("Mailbox name. Defaults to INBOX."),
				"uid":            numberProp("IMAP UID of the message to read for generic IMAP accounts."),
				"id":             stringProp("Gmail API message id from email_search for Gmail accounts."),
				"gmail_id":       stringProp("Alias for id when reading Gmail API messages."),
				"max_body_chars": numberProp("Maximum body characters, capped at 100000. Defaults to 20000."),
			}, nil),
			ReadOnly: true,
			Risk:     "read",
		},
	}
}

func isEmailTool(toolName string) bool {
	switch strings.TrimSpace(toolName) {
	case "email_accounts", "email_search", "email_read", "email_send":
		return true
	default:
		return false
	}
}

func callEmailTool(toolName string, arguments map[string]any) shared.ToolResult {
	switch strings.TrimSpace(toolName) {
	case "email_accounts":
		return callEmailAccounts(arguments)
	case "email_search":
		return callEmailSearch(arguments)
	case "email_read":
		return callEmailRead(arguments)
	case "email_send":
		return emailError("email_send", "email_send is disabled by default; leftpanel email MCP is read-only.")
	default:
		return shared.ToolResult{Name: toolName, Text: "Unknown email tool: " + toolName, IsError: true}
	}
}

func callEmailAccounts(map[string]any) shared.ToolResult {
	accounts, err := loadEmailAccounts()
	if err != nil {
		return emailError("email_accounts", err.Error())
	}
	if len(accounts) == 0 {
		return emailError("email_accounts", "No email accounts configured. Add email account metadata to leftpanel/config.toml.")
	}
	public := make([]map[string]any, 0, len(accounts))
	lines := make([]string, 0, len(accounts))
	for _, account := range accounts {
		public = append(public, account.publicMap())
		lines = append(lines, fmt.Sprintf("- %s: %s (%s)", account.ID, account.Address, account.Provider))
	}
	return shared.ToolResult{
		Name: "email_accounts",
		Text: strings.Join(lines, "\n"),
		Data: map[string]any{"accounts": public},
	}
}

func callEmailSearch(arguments map[string]any) shared.ToolResult {
	account, err := selectEmailAccount(arguments)
	if err != nil {
		return emailError("email_search", err.Error())
	}
	if isGmailAccount(account) {
		return callGmailEmailSearch(account, arguments)
	}
	client, err := dialIMAP(account)
	if err != nil {
		return emailError("email_search", err.Error())
	}
	defer closeIMAP(client)

	mailbox := mailboxFromArgsForAccount(account, arguments)
	if _, err := client.Select(mailbox, nil).Wait(); err != nil {
		return emailError("email_search", err.Error())
	}

	criteria, err := searchCriteriaFromArgs(arguments)
	if err != nil {
		return emailError("email_search", err.Error())
	}
	searchData, err := client.UIDSearch(criteria, nil).Wait()
	if err != nil {
		return emailError("email_search", err.Error())
	}
	uids := searchData.AllUIDs()
	slices.SortFunc(uids, func(a, b imap.UID) int { return int(b) - int(a) })
	limit := intArgument(arguments, "limit", 10, 1, 50)
	matchedCount := len(uids)
	uids, _ = limitUIDs(uids, limit)
	if len(uids) == 0 {
		return shared.ToolResult{
			Name: "email_search",
			Text: "No messages matched.",
			Data: map[string]any{"account": account.ID, "mailbox": mailbox, "matched_count": matchedCount, "returned_count": 0, "limit": limit, "messages": []map[string]any{}},
		}
	}

	messages, err := fetchSummaries(client, uids)
	if err != nil {
		return emailError("email_search", err.Error())
	}
	lines := make([]string, 0, len(messages))
	for _, msg := range messages {
		lines = append(lines, fmt.Sprintf("- UID %v: %s", msg["uid"], msg["subject"]))
	}
	return shared.ToolResult{
		Name: "email_search",
		Text: strings.Join(lines, "\n"),
		Data: map[string]any{"account": account.ID, "mailbox": mailbox, "matched_count": matchedCount, "returned_count": len(messages), "limit": limit, "messages": messages},
	}
}

func callEmailRead(arguments map[string]any) shared.ToolResult {
	account, err := selectEmailAccount(arguments)
	if err != nil {
		return emailError("email_read", err.Error())
	}
	if isGmailAccount(account) {
		return callGmailEmailRead(account, arguments)
	}
	uidValue, ok := numericArgument(arguments["uid"])
	if !ok || uidValue <= 0 {
		return emailError("email_read", "uid is required")
	}
	const maxIMAPUID = int64(1<<32 - 1)
	if uidValue > maxIMAPUID {
		return emailError("email_read", "uid is out of range")
	}
	client, err := dialIMAP(account)
	if err != nil {
		return emailError("email_read", err.Error())
	}
	defer closeIMAP(client)

	mailbox := mailboxFromArgsForAccount(account, arguments)
	if _, err := client.Select(mailbox, nil).Wait(); err != nil {
		return emailError("email_read", err.Error())
	}

	section := &imap.FetchItemBodySection{Peek: true}
	msgs, err := client.Fetch(imap.UIDSetNum(imap.UID(uidValue)), &imap.FetchOptions{
		Envelope:     true,
		Flags:        true,
		InternalDate: true,
		RFC822Size:   true,
		UID:          true,
		BodySection:  []*imap.FetchItemBodySection{section},
	}).Collect()
	if err != nil {
		return emailError("email_read", err.Error())
	}
	if len(msgs) == 0 {
		return emailError("email_read", fmt.Sprintf("message UID %d not found", uidValue))
	}
	msg := msgs[0]
	maxChars := intArgument(arguments, "max_body_chars", 20000, 1000, 100000)
	body := parseEmailBody(msg.FindBodySection(section), maxChars)
	summary := messageSummary(msg)
	summary["body_text"] = body.Text
	summary["body_html"] = body.HTML
	summary["body_truncated"] = body.Truncated
	return shared.ToolResult{
		Name: "email_read",
		Text: firstNonEmpty(body.Text, body.HTML, fmt.Sprintf("Read UID %d.", uidValue)),
		Data: map[string]any{"account": account.ID, "mailbox": mailbox, "message": summary},
	}
}

func emailAccountsFromEnv(env map[string]string) ([]emailAccount, error) {
	ids := splitCSV(firstNonEmpty(env["EMAIL_ACCOUNTS"], env["EMAIL_ACCOUNT_IDS"]))
	if len(ids) == 0 && hasSingleEmailConfig(env) {
		ids = []string{firstNonEmpty(env["EMAIL_ACCOUNT_ID"], "default")}
	}
	accounts := make([]emailAccount, 0, len(ids))
	var errs []string
	for _, id := range ids {
		account, err := emailAccountFromEnv(env, id, len(ids) == 1 && id == firstNonEmpty(env["EMAIL_ACCOUNT_ID"], "default"))
		if err != nil {
			errs = append(errs, err.Error())
			continue
		}
		accounts = append(accounts, account)
	}
	if len(errs) > 0 {
		return accounts, errors.New(strings.Join(errs, "; "))
	}
	return accounts, nil
}

func emailAccountFromEnv(env map[string]string, id string, allowUnprefixed bool) (emailAccount, error) {
	id = strings.TrimSpace(id)
	if id == "" {
		return emailAccount{}, fmt.Errorf("email account id is required")
	}
	getWithKey := func(key string) (string, string) {
		fullKey := "EMAIL_" + envID(id) + "_" + key
		value := strings.TrimSpace(env[fullKey])
		if value == "" && allowUnprefixed {
			fullKey = "EMAIL_" + key
			value = strings.TrimSpace(env[fullKey])
		}
		return value, fullKey
	}
	get := func(key string) string {
		value, _ := getWithKey(key)
		return value
	}
	firstSecret := func(keys ...string) (string, string) {
		for _, key := range keys {
			value, fullKey := getWithKey(key)
			if value != "" {
				return value, fullKey
			}
		}
		return "", ""
	}

	googleTokenJSON, googleTokenKey := firstSecret("GOOGLE_TOKEN_JSON")
	googleClientID, googleClientIDKey := firstSecret("GOOGLE_CLIENT_ID")
	googleSecret, googleSecretKey := firstSecret("GOOGLE_CLIENT_SECRET")
	address := firstNonEmpty(get("ADDRESS"), get("EMAIL"))
	provider := strings.ToLower(firstNonEmpty(get("PROVIDER"), detectEmailProvider(address), "generic"))
	account := emailAccount{
		ID:       id,
		Label:    firstNonEmpty(get("LABEL"), id),
		Provider: provider,
		Address:  address,
		From:     firstNonEmpty(get("FROM"), address),
		Username: firstNonEmpty(get("USERNAME"), get("IMAP_USERNAME"), address),
		Password: firstNonEmpty(get("PASSWORD"), get("APP_PASSWORD"), get("TOKEN")),
		IMAPHost: get("IMAP_HOST"),
		IMAPTLS:  normalizeTLSMode(get("IMAP_TLS"), "ssl"),

		Google: googleauth.Account{
			ID:              id,
			Address:         address,
			TokenJSON:       googleTokenJSON,
			ClientID:        googleClientID,
			ClientSecret:    googleSecret,
			TokenKey:        googleTokenKey,
			ClientIDKey:     googleClientIDKey,
			ClientSecretKey: googleSecretKey,
		},
	}
	if account.Provider == "gmail" {
		if account.IMAPHost == "" {
			account.IMAPHost = "imap.gmail.com"
		}
	}
	account.IMAPPort = intEnv(firstNonEmpty(get("IMAP_PORT"), get("PORT")), defaultIMAPPort(account.IMAPTLS))

	if account.Address == "" {
		return emailAccount{}, fmt.Errorf("EMAIL_%s_ADDRESS is required", envID(id))
	}
	if account.Password == "" && (!isGmailAccount(account) || !account.hasGoogleToken()) {
		if isGmailAccount(account) {
			return emailAccount{}, fmt.Errorf("GOOGLE_%s_TOKEN_JSON is required", envID(id))
		}
		return emailAccount{}, fmt.Errorf("EMAIL_%s_PASSWORD is required", envID(id))
	}
	if account.IMAPHost == "" {
		return emailAccount{}, fmt.Errorf("EMAIL_%s_IMAP_HOST is required", envID(id))
	}
	return account, nil
}

func loadEmailAccounts() ([]emailAccount, error) {
	cfg, err := appconfig.Current()
	if err != nil {
		return nil, err
	}
	return emailAccountsFromEnv(loadEmailEnv(cfg, secrets.NewResolver()))
}

func loadEmailEnv(cfg appconfig.Config, resolver secrets.Resolver) map[string]string {
	env := cfg.EmailEnv()
	ids := splitCSV(firstNonEmpty(env["EMAIL_ACCOUNTS"], env["EMAIL_ACCOUNT_IDS"]))
	if len(ids) == 0 {
		if id := strings.TrimSpace(env["EMAIL_ACCOUNT_ID"]); id != "" {
			ids = []string{id}
		}
	}
	for _, id := range ids {
		prefix := "EMAIL_" + envID(id) + "_"
		for _, key := range []string{"PASSWORD", "APP_PASSWORD", "TOKEN"} {
			fullKey := prefix + key
			if value, ok := resolver.Lookup(fullKey); ok {
				env[fullKey] = value
			}
		}
		googlePrefix := "GOOGLE_" + envID(id) + "_"
		for _, key := range []string{"TOKEN_JSON", "CLIENT_ID", "CLIENT_SECRET"} {
			fullKey := googlePrefix + key
			if value, ok := resolver.Lookup(fullKey); ok {
				env[prefix+"GOOGLE_"+key] = value
			}
		}
	}
	return env
}

func selectEmailAccount(arguments map[string]any) (emailAccount, error) {
	accounts, err := loadEmailAccounts()
	if err != nil {
		return emailAccount{}, err
	}
	if len(accounts) == 0 {
		return emailAccount{}, fmt.Errorf("no email accounts configured; add email account metadata to leftpanel/config.toml")
	}
	id := normalizeAccountSelector(stringArgument(arguments, "account"))
	if id == "" {
		return defaultEmailAccount(accounts), nil
	}
	for _, account := range accounts {
		if emailAccountMatchesSelector(account, id) {
			return account, nil
		}
	}
	return emailAccount{}, fmt.Errorf("unknown email account %q; available accounts: %s", id, emailAccountIDList(accounts))
}

func defaultEmailAccount(accounts []emailAccount) emailAccount {
	for _, account := range accounts {
		if isPersonalEmailAccount(account) {
			return account
		}
	}
	return accounts[0]
}

func normalizeAccountSelector(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	switch value {
	case "", "default", "null", "none", "auto":
		return ""
	default:
		return value
	}
}

func emailAccountMatchesSelector(account emailAccount, selector string) bool {
	if selector == "" {
		return false
	}
	if normalizeSelector(account.ID) == selector ||
		normalizeSelector(account.Label) == selector ||
		normalizeSelector(account.Address) == selector ||
		normalizeSelector(account.From) == selector ||
		normalizeSelector(account.Username) == selector {
		return true
	}
	return selector == "personal" && isPersonalEmailAccount(account)
}

func isPersonalEmailAccount(account emailAccount) bool {
	for _, value := range []string{account.ID, account.Label, account.Address, account.From, account.Username} {
		normalized := normalizeSelector(value)
		if normalized == "personal" ||
			strings.Contains(normalized, "personal") ||
			strings.Contains(normalized, "gmail.com") {
			return true
		}
	}
	return false
}

func normalizeSelector(value string) string {
	return strings.ToLower(strings.TrimSpace(value))
}

func emailAccountIDList(accounts []emailAccount) string {
	ids := make([]string, 0, len(accounts))
	for _, account := range accounts {
		ids = append(ids, account.ID)
	}
	return strings.Join(ids, ", ")
}

func isGmailAccount(account emailAccount) bool {
	return strings.EqualFold(account.Provider, "gmail")
}

func (account emailAccount) hasGoogleToken() bool {
	return strings.TrimSpace(account.Google.TokenJSON) != ""
}

func dialIMAP(account emailAccount) (*imapclient.Client, error) {
	if account.IMAPHost == "" {
		return nil, fmt.Errorf("account %s has no IMAP host configured", account.ID)
	}
	address := net.JoinHostPort(account.IMAPHost, strconv.Itoa(account.IMAPPort))
	options := &imapclient.Options{
		Dialer:      &net.Dialer{Timeout: 30 * time.Second},
		TLSConfig:   &tls.Config{ServerName: account.IMAPHost, MinVersion: tls.VersionTLS12},
		WordDecoder: &mime.WordDecoder{CharsetReader: charset.Reader},
	}
	var (
		client *imapclient.Client
		err    error
	)
	switch account.IMAPTLS {
	case "none":
		client, err = imapclient.DialInsecure(address, options)
	case "starttls":
		client, err = imapclient.DialStartTLS(address, options)
	default:
		client, err = imapclient.DialTLS(address, options)
	}
	if err != nil {
		return nil, err
	}
	if err := client.Login(account.Username, account.Password).Wait(); err != nil {
		_ = client.Close()
		return nil, err
	}
	return client, nil
}

func closeIMAP(client *imapclient.Client) {
	if client == nil {
		return
	}
	_ = client.Logout().Wait()
	_ = client.Close()
}

func searchCriteriaFromArgs(arguments map[string]any) (*imap.SearchCriteria, error) {
	criteria := &imap.SearchCriteria{}
	query := parseGmailStyleSearchQuery(stringArgument(arguments, "query"))
	if query.Text != "" {
		criteria.Text = []string{query.Text}
	}
	if from := firstNonEmpty(stringArgument(arguments, "from"), query.From); from != "" {
		criteria.Header = append(criteria.Header, imap.SearchCriteriaHeaderField{Key: "From", Value: from})
	}
	if to := firstNonEmpty(stringArgument(arguments, "to"), query.To); to != "" {
		criteria.Header = append(criteria.Header, imap.SearchCriteriaHeaderField{Key: "To", Value: to})
	}
	if subject := firstNonEmpty(stringArgument(arguments, "subject"), query.Subject); subject != "" {
		criteria.Header = append(criteria.Header, imap.SearchCriteriaHeaderField{Key: "Subject", Value: subject})
	}
	state := query.State
	if boolArgument(arguments, "unread_only") {
		state = "unread"
	}
	switch state {
	case "unread":
		criteria.NotFlag = []imap.Flag{imap.FlagSeen}
	case "read":
		criteria.Flag = []imap.Flag{imap.FlagSeen}
	}
	if since := firstNonEmpty(stringArgument(arguments, "since"), query.After); since != "" {
		parsed, err := parseDateArgument(since)
		if err != nil {
			return nil, err
		}
		criteria.Since = parsed
	}
	if before := query.Before; before != "" {
		parsed, err := parseDateArgument(before)
		if err != nil {
			return nil, err
		}
		criteria.Before = parsed
	}
	if query.HasAttachment {
		criteria.Or = append(criteria.Or, [2]imap.SearchCriteria{
			{Header: []imap.SearchCriteriaHeaderField{{Key: "Content-Type", Value: "multipart/mixed"}}},
			{Header: []imap.SearchCriteriaHeaderField{{Key: "Content-Disposition", Value: "attachment"}}},
		})
	}
	return criteria, nil
}

func mailboxFromArgs(arguments map[string]any) string {
	if mailbox := stringArgument(arguments, "mailbox"); mailbox != "" {
		return mailbox
	}
	if label := parseGmailStyleSearchQuery(stringArgument(arguments, "query")).Label; label != "" {
		return label
	}
	return "INBOX"
}

func mailboxFromArgsForAccount(account emailAccount, arguments map[string]any) string {
	mailbox := mailboxFromArgs(arguments)
	if strings.EqualFold(account.Provider, "gmail") {
		switch normalizeMailboxAlias(mailbox) {
		case "all", "allmail", "alllabels":
			return "[Gmail]/All Mail"
		}
	}
	return mailbox
}

func normalizeMailboxAlias(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	var b strings.Builder
	for _, r := range value {
		if r >= 'a' && r <= 'z' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

type gmailStyleSearchQuery struct {
	Text          string
	From          string
	To            string
	Subject       string
	After         string
	Before        string
	State         string
	Label         string
	HasAttachment bool
}

func parseGmailStyleSearchQuery(raw string) gmailStyleSearchQuery {
	tokens := splitSearchQueryTokens(raw)
	var parsed gmailStyleSearchQuery
	remaining := make([]string, 0, len(tokens))
	for _, token := range tokens {
		key, value, ok := strings.Cut(token, ":")
		if !ok {
			remaining = append(remaining, token)
			continue
		}
		key = strings.ToLower(strings.TrimSpace(key))
		value = strings.TrimSpace(value)
		if value == "" {
			continue
		}
		switch key {
		case "from":
			parsed.From = value
		case "to":
			parsed.To = value
		case "subject":
			parsed.Subject = value
		case "after", "newer":
			parsed.After = value
		case "before", "older":
			parsed.Before = value
		case "is":
			state := strings.ToLower(value)
			if state == "unread" || state == "read" {
				parsed.State = state
			} else {
				remaining = append(remaining, token)
			}
		case "label":
			parsed.Label = value
		case "has":
			if strings.EqualFold(value, "attachment") {
				parsed.HasAttachment = true
				continue
			}
			remaining = append(remaining, token)
		default:
			remaining = append(remaining, token)
		}
	}
	parsed.Text = strings.Join(remaining, " ")
	return parsed
}

func splitSearchQueryTokens(raw string) []string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	tokens := []string{}
	var current strings.Builder
	var quote rune
	escaped := false
	for _, r := range raw {
		if escaped {
			current.WriteRune(r)
			escaped = false
			continue
		}
		if r == '\\' && quote != 0 {
			escaped = true
			continue
		}
		if quote != 0 {
			if r == quote {
				quote = 0
			} else {
				current.WriteRune(r)
			}
			continue
		}
		if r == '"' || r == '\'' {
			quote = r
			continue
		}
		if r == ' ' || r == '\t' || r == '\n' || r == '\r' {
			if token := strings.TrimSpace(current.String()); token != "" {
				tokens = append(tokens, token)
				current.Reset()
			}
			continue
		}
		current.WriteRune(r)
	}
	if token := strings.TrimSpace(current.String()); token != "" {
		tokens = append(tokens, token)
	}
	return tokens
}

type gmailClient interface {
	listMessages(ctx context.Context, query string, limit int) (gmailListResult, error)
	getMessage(ctx context.Context, id string, includeBody bool, maxBodyChars int) (gmailMessage, error)
}

type gmailListResult struct {
	Messages []gmailListedMessage
	Estimate int64
}

type gmailListedMessage struct {
	ID       string
	ThreadID string
}

type gmailMessage struct {
	ID            string
	ThreadID      string
	Subject       string
	From          string
	To            string
	Date          string
	MessageID     string
	Snippet       string
	BodyText      string
	BodyHTML      string
	BodyTruncated bool
	InternalDate  string
	Size          int64
	LabelIDs      []string
}

type gmailServiceClient struct {
	service *gmail.Service
}

var newGmailClient = func(ctx context.Context, account emailAccount) (gmailClient, error) {
	httpClient, err := gmailOAuthHTTPClient(ctx, account)
	if err != nil {
		return nil, err
	}
	service, err := gmail.NewService(ctx, option.WithHTTPClient(httpClient))
	if err != nil {
		return nil, err
	}
	return gmailServiceClient{service: service}, nil
}

func gmailOAuthHTTPClient(ctx context.Context, account emailAccount) (*http.Client, error) {
	return googleauth.NewHTTPClient(ctx, account.Google, []string{gmail.GmailReadonlyScope})
}

func (c gmailServiceClient) listMessages(ctx context.Context, query string, limit int) (gmailListResult, error) {
	call := c.service.Users.Messages.List("me").MaxResults(int64(limit))
	if strings.TrimSpace(query) != "" {
		call = call.Q(query)
	}
	response, err := call.Context(ctx).Do()
	if err != nil {
		return gmailListResult{}, err
	}
	out := gmailListResult{Estimate: response.ResultSizeEstimate, Messages: make([]gmailListedMessage, 0, len(response.Messages))}
	for _, message := range response.Messages {
		if message == nil || strings.TrimSpace(message.Id) == "" {
			continue
		}
		out.Messages = append(out.Messages, gmailListedMessage{ID: message.Id, ThreadID: message.ThreadId})
	}
	return out, nil
}

func (c gmailServiceClient) getMessage(ctx context.Context, id string, includeBody bool, maxBodyChars int) (gmailMessage, error) {
	call := c.service.Users.Messages.Get("me", id)
	if includeBody {
		call = call.Format("full")
	} else {
		call = call.Format("metadata").MetadataHeaders("Subject", "From", "To", "Date", "Message-ID")
	}
	message, err := call.Context(ctx).Do()
	if err != nil {
		return gmailMessage{}, err
	}
	return gmailMessageFromAPI(message, includeBody, maxBodyChars), nil
}

func callGmailEmailSearch(account emailAccount, arguments map[string]any) shared.ToolResult {
	limit := intArgument(arguments, "limit", 10, 1, 50)
	query := stringArgument(arguments, "query")
	ctx := context.Background()
	client, err := newGmailClient(ctx, account)
	if err != nil {
		return emailError("email_search", err.Error())
	}
	list, err := client.listMessages(ctx, query, limit)
	if err != nil {
		return emailError("email_search", err.Error())
	}
	if len(list.Messages) == 0 {
		return shared.ToolResult{
			Name: "email_search",
			Text: "No messages matched.",
			Data: map[string]any{"account": account.ID, "mailbox": gmailMailboxLabel(arguments), "matched_count": list.Estimate, "returned_count": 0, "limit": limit, "messages": []map[string]any{}},
		}
	}

	messages := make([]map[string]any, 0, len(list.Messages))
	lines := make([]string, 0, len(list.Messages))
	for _, listed := range list.Messages {
		message, err := client.getMessage(ctx, listed.ID, false, 0)
		if err != nil {
			return emailError("email_search", err.Error())
		}
		if message.ID == "" {
			message.ID = listed.ID
		}
		if message.ThreadID == "" {
			message.ThreadID = listed.ThreadID
		}
		summary := gmailMessageSummary(message, false)
		messages = append(messages, summary)
		lines = append(lines, fmt.Sprintf("- Gmail %s: %s", message.ID, firstNonEmpty(message.Subject, "(no subject)")))
	}
	matchedCount := list.Estimate
	if matchedCount == 0 {
		matchedCount = int64(len(list.Messages))
	}
	return shared.ToolResult{
		Name: "email_search",
		Text: strings.Join(lines, "\n"),
		Data: map[string]any{"account": account.ID, "mailbox": gmailMailboxLabel(arguments), "matched_count": matchedCount, "returned_count": len(messages), "limit": limit, "messages": messages},
	}
}

func callGmailEmailRead(account emailAccount, arguments map[string]any) shared.ToolResult {
	id := firstNonEmpty(stringArgument(arguments, "id"), stringArgument(arguments, "gmail_id"))
	if id == "" {
		return emailError("email_read", "id is required for Gmail accounts; pass the id or gmail_id returned by email_search")
	}
	maxChars := intArgument(arguments, "max_body_chars", 20000, 1000, 100000)
	ctx := context.Background()
	client, err := newGmailClient(ctx, account)
	if err != nil {
		return emailError("email_read", err.Error())
	}
	message, err := client.getMessage(ctx, id, true, maxChars)
	if err != nil {
		return emailError("email_read", err.Error())
	}
	if message.ID == "" {
		message.ID = id
	}
	summary := gmailMessageSummary(message, true)
	return shared.ToolResult{
		Name: "email_read",
		Text: firstNonEmpty(message.BodyText, message.BodyHTML, message.Snippet, fmt.Sprintf("Read Gmail message %s.", id)),
		Data: map[string]any{"account": account.ID, "mailbox": gmailMailboxLabel(arguments), "message": summary},
	}
}

func gmailMailboxLabel(arguments map[string]any) string {
	return firstNonEmpty(stringArgument(arguments, "mailbox"), "gmail")
}

func gmailMessageFromAPI(message *gmail.Message, includeBody bool, maxBodyChars int) gmailMessage {
	if message == nil {
		return gmailMessage{}
	}
	headers := gmailHeaders(message.Payload)
	out := gmailMessage{
		ID:           message.Id,
		ThreadID:     message.ThreadId,
		Subject:      headers["subject"],
		From:         headers["from"],
		To:           headers["to"],
		Date:         headers["date"],
		MessageID:    firstNonEmpty(headers["message-id"], headers["message_id"]),
		Snippet:      message.Snippet,
		Size:         message.SizeEstimate,
		LabelIDs:     append([]string{}, message.LabelIds...),
		InternalDate: gmailInternalDate(message.InternalDate),
	}
	if includeBody {
		out.BodyText, out.BodyHTML, out.BodyTruncated = gmailBodies(message.Payload, maxBodyChars)
	}
	return out
}

func gmailHeaders(part *gmail.MessagePart) map[string]string {
	headers := map[string]string{}
	if part == nil {
		return headers
	}
	for _, header := range part.Headers {
		if header == nil {
			continue
		}
		headers[strings.ToLower(strings.TrimSpace(header.Name))] = strings.TrimSpace(header.Value)
	}
	return headers
}

func gmailInternalDate(epochMillis int64) string {
	if epochMillis <= 0 {
		return ""
	}
	return time.UnixMilli(epochMillis).Format(time.RFC3339)
}

func gmailBodies(part *gmail.MessagePart, maxChars int) (string, string, bool) {
	if part == nil {
		return "", "", false
	}
	var text, html string
	var truncated bool
	var walk func(*gmail.MessagePart)
	walk = func(current *gmail.MessagePart) {
		if current == nil {
			return
		}
		if current.Body != nil && current.Body.Data != "" {
			body, ok := decodeGmailBody(current.Body.Data)
			if ok {
				value, wasTruncated := truncateOutput(body, maxChars)
				truncated = truncated || wasTruncated
				switch strings.ToLower(current.MimeType) {
				case "text/plain":
					if text == "" {
						text = value
					}
				case "text/html":
					if html == "" {
						html = value
					}
				}
			}
		}
		for _, child := range current.Parts {
			walk(child)
		}
	}
	walk(part)
	return text, html, truncated
}

func decodeGmailBody(raw string) (string, bool) {
	data, err := base64.RawURLEncoding.DecodeString(raw)
	if err != nil {
		data, err = base64.URLEncoding.DecodeString(raw)
	}
	if err != nil {
		return "", false
	}
	return string(data), true
}

func gmailMessageSummary(message gmailMessage, includeBody bool) map[string]any {
	out := map[string]any{
		"id":        message.ID,
		"gmail_id":  message.ID,
		"thread_id": message.ThreadID,
		"snippet":   message.Snippet,
	}
	if message.Subject != "" {
		out["subject"] = message.Subject
	}
	if message.From != "" {
		out["from"] = message.From
	}
	if message.To != "" {
		out["to"] = message.To
	}
	if message.Date != "" {
		out["date"] = message.Date
	}
	if message.MessageID != "" {
		out["message_id"] = message.MessageID
	}
	if message.InternalDate != "" {
		out["internal_date"] = message.InternalDate
	}
	if message.Size > 0 {
		out["size"] = message.Size
	}
	if len(message.LabelIDs) > 0 {
		out["label_ids"] = message.LabelIDs
	}
	if includeBody {
		out["body_text"] = message.BodyText
		out["body_html"] = message.BodyHTML
		out["body_truncated"] = message.BodyTruncated
	}
	return out
}

func fetchSummaries(client *imapclient.Client, uids []imap.UID) ([]map[string]any, error) {
	msgs, err := client.Fetch(imap.UIDSetNum(uids...), &imap.FetchOptions{
		Envelope:     true,
		Flags:        true,
		InternalDate: true,
		RFC822Size:   true,
		UID:          true,
	}).Collect()
	if err != nil {
		return nil, err
	}
	slices.SortFunc(msgs, func(a, b *imapclient.FetchMessageBuffer) int { return int(b.UID) - int(a.UID) })
	out := make([]map[string]any, 0, len(msgs))
	for _, msg := range msgs {
		out = append(out, messageSummary(msg))
	}
	return out, nil
}

func limitUIDs(uids []imap.UID, limit int) ([]imap.UID, int) {
	matched := len(uids)
	if limit < 0 {
		limit = 0
	}
	if len(uids) > limit {
		return uids[:limit], matched
	}
	return uids, matched
}

func messageSummary(msg *imapclient.FetchMessageBuffer) map[string]any {
	out := map[string]any{
		"uid":           uint32(msg.UID),
		"seq_num":       msg.SeqNum,
		"flags":         flagsToStrings(msg.Flags),
		"internal_date": msg.InternalDate.Format(time.RFC3339),
		"size":          msg.RFC822Size,
	}
	if env := msg.Envelope; env != nil {
		out["subject"] = env.Subject
		out["from"] = addressesToStrings(env.From)
		out["to"] = addressesToStrings(env.To)
		out["cc"] = addressesToStrings(env.Cc)
		out["date"] = env.Date.Format(time.RFC3339)
		out["message_id"] = env.MessageID
		out["in_reply_to"] = env.InReplyTo
	}
	return out
}

type parsedEmailBody struct {
	Text      string
	HTML      string
	Truncated bool
}

func parseEmailBody(raw []byte, maxChars int) parsedEmailBody {
	if len(raw) == 0 {
		return parsedEmailBody{}
	}
	reader, err := emersionmail.CreateReader(bytes.NewReader(raw))
	if err != nil {
		text, truncated := truncateOutput(string(raw), maxChars)
		return parsedEmailBody{Text: text, Truncated: truncated}
	}
	defer func() {
		_ = reader.Close()
	}()

	var out parsedEmailBody
	for {
		part, err := reader.NextPart()
		if err == io.EOF {
			break
		}
		if err != nil {
			break
		}
		inline, ok := part.Header.(*emersionmail.InlineHeader)
		if !ok {
			continue
		}
		contentType, _, _ := inline.ContentType()
		body, truncated := readBounded(part.Body, maxChars)
		out.Truncated = out.Truncated || truncated
		switch strings.ToLower(contentType) {
		case "text/plain":
			if out.Text == "" {
				out.Text = body
			}
		case "text/html":
			if out.HTML == "" {
				out.HTML = body
			}
		}
	}
	if out.Text == "" && out.HTML == "" {
		text, truncated := readBounded(bytes.NewReader(raw), maxChars)
		out.Text = text
		out.Truncated = out.Truncated || truncated
	}
	return out
}

func (account emailAccount) publicMap() map[string]any {
	canRead := account.IMAPHost != ""
	authSource := "secret-service"
	if isGmailAccount(account) {
		canRead = account.hasGoogleToken()
		if canRead {
			authSource = "google-oauth-token"
		}
	}
	return map[string]any{
		"id":          account.ID,
		"label":       account.Label,
		"provider":    account.Provider,
		"address":     account.Address,
		"from":        account.From,
		"imap_host":   account.IMAPHost,
		"imap_port":   account.IMAPPort,
		"imap_tls":    account.IMAPTLS,
		"can_read":    canRead,
		"can_send":    false,
		"auth_source": authSource,
	}
}

func hasSingleEmailConfig(env map[string]string) bool {
	for _, key := range []string{"EMAIL_ADDRESS", "EMAIL_USERNAME", "EMAIL_PASSWORD", "EMAIL_APP_PASSWORD"} {
		if strings.TrimSpace(env[key]) != "" {
			return true
		}
	}
	return false
}

func envID(id string) string {
	id = strings.ToUpper(strings.TrimSpace(id))
	var b strings.Builder
	for _, r := range id {
		if (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
		} else {
			b.WriteByte('_')
		}
	}
	return strings.Trim(b.String(), "_")
}

func detectEmailProvider(address string) string {
	lower := strings.ToLower(strings.TrimSpace(address))
	if strings.HasSuffix(lower, "@gmail.com") || strings.HasSuffix(lower, "@googlemail.com") {
		return "gmail"
	}
	return ""
}

func normalizeTLSMode(value string, fallback string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "tls", "ssl", "implicit":
		return "ssl"
	case "starttls", "start_tls", "true", "":
		return fallback
	case "none", "plain", "insecure", "false":
		return "none"
	default:
		return fallback
	}
}

func defaultIMAPPort(mode string) int {
	if mode == "ssl" {
		return 993
	}
	return 143
}

func parseDateArgument(value string) (time.Time, error) {
	for _, layout := range []string{"2006-01-02", "2006/01/02", time.RFC3339, time.RFC1123Z, time.RFC1123} {
		if parsed, err := time.Parse(layout, value); err == nil {
			return parsed, nil
		}
	}
	return time.Time{}, fmt.Errorf("invalid date %q", value)
}

func splitCSV(value string) []string {
	parts := strings.FieldsFunc(value, func(r rune) bool { return r == ',' || r == ';' || r == ' ' || r == '\n' || r == '\t' })
	out := make([]string, 0, len(parts))
	seen := map[string]bool{}
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part == "" || seen[part] {
			continue
		}
		seen[part] = true
		out = append(out, part)
	}
	return out
}

func intEnv(value string, fallback int) int {
	if n, err := strconv.Atoi(strings.TrimSpace(value)); err == nil && n > 0 {
		return n
	}
	return fallback
}

func intArgument(args map[string]any, key string, fallback int, minValue int, maxValue int) int {
	raw, ok := numericArgument(args[key])
	if !ok {
		return fallback
	}
	value := int(raw)
	if value < minValue {
		return minValue
	}
	if value > maxValue {
		return maxValue
	}
	return value
}

func boolArgument(args map[string]any, key string) bool {
	if args == nil {
		return false
	}
	switch v := args[key].(type) {
	case bool:
		return v
	case string:
		parsed, _ := strconv.ParseBool(strings.TrimSpace(v))
		return parsed
	default:
		return false
	}
}

func addressesToStrings(values []imap.Address) []string {
	out := make([]string, 0, len(values))
	for _, addr := range values {
		if addr.IsGroupStart() || addr.IsGroupEnd() {
			continue
		}
		text := addr.Addr()
		if addr.Name != "" {
			text = fmt.Sprintf("%s <%s>", addr.Name, text)
		}
		out = append(out, text)
	}
	return out
}

func flagsToStrings(values []imap.Flag) []string {
	out := make([]string, 0, len(values))
	for _, flag := range values {
		out = append(out, string(flag))
	}
	return out
}

func readBounded(r io.Reader, maxChars int) (string, bool) {
	limited := io.LimitReader(r, int64(maxChars)+1)
	raw, _ := io.ReadAll(limited)
	text := string(raw)
	if len(text) > maxChars {
		return text[:maxChars], true
	}
	return text, false
}

func objectSchema(properties map[string]any, required []any) map[string]any {
	if properties == nil {
		properties = map[string]any{}
	}
	out := map[string]any{
		"type":       "object",
		"properties": properties,
	}
	if len(required) > 0 {
		out["required"] = required
	}
	return out
}

func emailAccountProp() map[string]any {
	description := "Email account id. Use null/default to auto-select the personal account when configured."
	prop := map[string]any{
		"type":        []any{"string", "null"},
		"description": description,
	}

	accounts, err := loadEmailAccounts()
	if err != nil || len(accounts) == 0 {
		return prop
	}

	enum := []any{nil}
	labels := make([]string, 0, len(accounts))
	for _, account := range accounts {
		enum = append(enum, account.ID)
		labels = append(labels, fmt.Sprintf("%s = %s", account.ID, firstNonEmpty(account.Label, account.Address, account.ID)))
	}
	prop["enum"] = enum
	prop["description"] = description + " Available accounts: " + strings.Join(labels, "; ") + "."
	return prop
}

func stringProp(description string) map[string]any {
	return map[string]any{"type": "string", "description": description}
}

func numberProp(description string) map[string]any {
	return map[string]any{"type": "number", "description": description}
}

func boolProp(description string) map[string]any {
	return map[string]any{"type": "boolean", "description": description}
}

func emailError(name, text string) shared.ToolResult {
	return shared.ToolResult{Name: name, Text: text, IsError: true}
}

func errorString(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}
