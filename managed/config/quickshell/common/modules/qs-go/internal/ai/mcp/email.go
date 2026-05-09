package mcp

import (
	"bytes"
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"mime"
	"net"
	"slices"
	"strconv"
	"strings"
	"time"

	imap "github.com/emersion/go-imap/v2"
	"github.com/emersion/go-imap/v2/imapclient"
	"github.com/emersion/go-message/charset"
	emersionmail "github.com/emersion/go-message/mail"

	"qs-go/internal/ai/shared"
	"qs-go/internal/appconfig"
	"qs-go/internal/secrets"
)

const (
	emailServerID    = "email"
	emailServerLabel = "Email Accounts"
)

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
		},
		{
			ServerID:      emailServerID,
			ServerLabel:   emailServerLabel,
			Name:          "email_search",
			QualifiedName: "email__email_search",
			Title:         "Search email",
			Description:   "Search an IMAP mailbox for messages by text, headers, unread state, and date.",
			InputSchema: objectSchema(map[string]any{
				"account":     stringProp("Optional account id. Defaults to the first configured account."),
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
		},
		{
			ServerID:      emailServerID,
			ServerLabel:   emailServerLabel,
			Name:          "email_read",
			QualifiedName: "email__email_read",
			Title:         "Read email",
			Description:   "Read one message by IMAP UID and return headers plus a bounded text/html body excerpt.",
			InputSchema: objectSchema(map[string]any{
				"account":        stringProp("Optional account id. Defaults to the first configured account."),
				"mailbox":        stringProp("Mailbox name. Defaults to INBOX."),
				"uid":            numberProp("IMAP UID of the message to read."),
				"max_body_chars": numberProp("Maximum body characters, capped at 100000. Defaults to 20000."),
			}, []any{"uid"}),
			ReadOnly: true,
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
	client, err := dialIMAP(account)
	if err != nil {
		return emailError("email_search", err.Error())
	}
	defer closeIMAP(client)

	mailbox := mailboxFromArgs(arguments)
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
	uidValue, ok := numericArgument(arguments["uid"])
	if !ok || uidValue <= 0 {
		return emailError("email_read", "uid is required")
	}
	client, err := dialIMAP(account)
	if err != nil {
		return emailError("email_read", err.Error())
	}
	defer closeIMAP(client)

	mailbox := firstNonEmpty(stringArgument(arguments, "mailbox"), "INBOX")
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
	get := func(key string) string {
		value := strings.TrimSpace(env["EMAIL_"+envID(id)+"_"+key])
		if value == "" && allowUnprefixed {
			value = strings.TrimSpace(env["EMAIL_"+key])
		}
		return value
	}

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
	if account.Password == "" {
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
	}
	return env
}

func selectEmailAccount(arguments map[string]any) (emailAccount, error) {
	accounts, err := loadEmailAccounts()
	if err != nil {
		return emailAccount{}, err
	}
	if len(accounts) == 0 {
		return emailAccount{}, fmt.Errorf("No email accounts configured. Add email account metadata to leftpanel/config.toml.")
	}
	id := stringArgument(arguments, "account")
	if id == "" {
		return accounts[0], nil
	}
	for _, account := range accounts {
		if account.ID == id {
			return account, nil
		}
	}
	return emailAccount{}, fmt.Errorf("unknown email account %q", id)
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

func boolState(value bool) string {
	if value {
		return "unread"
	}
	return ""
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
	defer reader.Close()

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
	return map[string]any{
		"id":          account.ID,
		"label":       account.Label,
		"provider":    account.Provider,
		"address":     account.Address,
		"from":        account.From,
		"imap_host":   account.IMAPHost,
		"imap_port":   account.IMAPPort,
		"imap_tls":    account.IMAPTLS,
		"can_read":    account.IMAPHost != "",
		"can_send":    false,
		"auth_source": "secret-service",
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

func intArgument(args map[string]any, key string, fallback int, min int, max int) int {
	raw, ok := numericArgument(args[key])
	if !ok {
		return fallback
	}
	value := int(raw)
	if value < min {
		return min
	}
	if value > max {
		return max
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
