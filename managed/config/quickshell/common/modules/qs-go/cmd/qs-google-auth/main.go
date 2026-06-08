// Package main provisions shared Google OAuth tokens for qs-go integrations.
package main

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"golang.org/x/oauth2"
	calendarapi "google.golang.org/api/calendar/v3"
	gmail "google.golang.org/api/gmail/v1"
	"google.golang.org/api/option"

	"qs-go/internal/appconfig"
	"qs-go/internal/googleauth"
	"qs-go/internal/secrets"
)

const (
	callbackPath   = "/oauth2callback"
	defaultTimeout = 10 * time.Minute
)

var googleScopes = []string{
	gmail.GmailReadonlyScope,
	calendarapi.CalendarCalendarlistReadonlyScope,
	calendarapi.CalendarEventsReadonlyScope,
}

type options struct {
	accountID  string
	configPath string
	clientJSON string
	timeout    time.Duration
	open       bool
	prompt     string
}

type oauthClientFile struct {
	ClientID     string `json:"client_id"`
	ClientSecret string `json:"client_secret"`
	Installed    struct {
		ClientID     string `json:"client_id"`
		ClientSecret string `json:"client_secret"`
	} `json:"installed"`
	Web struct {
		ClientID     string `json:"client_id"`
		ClientSecret string `json:"client_secret"`
	} `json:"web"`
}

type account struct {
	id      string
	address string
}

type oauthCallback struct {
	code  string
	state string
	err   string
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	if len(os.Args) < 2 {
		usage()
		return errors.New("subcommand is required")
	}
	switch os.Args[1] {
	case "provision":
		return provision(os.Args[2:])
	case "list-calendars":
		return listCalendars(os.Args[2:])
	default:
		usage()
		return fmt.Errorf("unknown subcommand %q", os.Args[1])
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: qs-google-auth provision --account ID --client-json PATH")
	fmt.Fprintln(os.Stderr, "       qs-google-auth list-calendars --account ID")
}

func provision(args []string) error {
	opts, err := parseFlags(args, true)
	if err != nil {
		return err
	}
	cfg, acct, err := loadAccount(opts)
	if err != nil {
		return err
	}
	_ = cfg
	clientID, clientSecret, err := loadOAuthClient(opts.clientJSON)
	if err != nil {
		return err
	}

	ctx, cancel := context.WithTimeout(context.Background(), opts.timeout)
	defer cancel()

	token, err := mintToken(ctx, acct, clientID, clientSecret, opts)
	if err != nil {
		return err
	}
	if strings.TrimSpace(token.RefreshToken) == "" {
		return errors.New("OAuth response did not include refresh_token; rerun with --prompt consent or revoke the old grant before retrying")
	}
	if err := verifyGoogleAccount(ctx, acct, clientID, clientSecret, token); err != nil {
		return err
	}
	if err := googleauth.StoreCredentials(secrets.NewStore(), acct.id, token, clientID, clientSecret); err != nil {
		return err
	}
	fmt.Fprintf(os.Stderr, "stored Google OAuth refresh config for %s (%s)\n", acct.id, acct.address)
	fmt.Fprintf(os.Stderr, "keys: %sTOKEN_JSON, %sCLIENT_ID, %sCLIENT_SECRET\n", googleauth.KeyPrefix(acct.id), googleauth.KeyPrefix(acct.id), googleauth.KeyPrefix(acct.id))
	return nil
}

func listCalendars(args []string) error {
	opts, err := parseFlags(args, false)
	if err != nil {
		return err
	}
	cfg, acct, err := loadAccount(opts)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	httpClient, err := googleauth.NewHTTPClient(ctx, googleauth.AccountFromResolver(acct.id, acct.address, secrets.NewResolver()), googleScopes)
	if err != nil {
		return err
	}
	service, err := calendarapi.NewService(ctx, option.WithHTTPClient(httpClient))
	if err != nil {
		return err
	}
	calendars, err := calendarSummaries(ctx, service)
	if err != nil {
		return err
	}
	_ = cfg
	raw, err := json.MarshalIndent(calendars, "", "  ")
	if err != nil {
		return err
	}
	fmt.Println(string(raw))
	return nil
}

func parseFlags(args []string, needsClient bool) (options, error) {
	fs := flag.NewFlagSet("qs-google-auth", flag.ContinueOnError)
	var opts options
	fs.StringVar(&opts.accountID, "account", "", "email account id from leftpanel/config.toml")
	fs.StringVar(&opts.configPath, "config", "", "leftpanel config path")
	fs.StringVar(&opts.clientJSON, "client-json", defaultClientPath(), "OAuth client JSON path")
	fs.DurationVar(&opts.timeout, "timeout", defaultTimeout, "maximum time to wait for browser authorization")
	fs.BoolVar(&opts.open, "open", false, "open the authorization URL with xdg-open")
	fs.StringVar(&opts.prompt, "prompt", "consent", "OAuth prompt value; use consent when minting refresh tokens")
	if err := fs.Parse(args); err != nil {
		return opts, err
	}
	if strings.TrimSpace(opts.accountID) == "" {
		return opts, errors.New("--account is required")
	}
	if needsClient && strings.TrimSpace(opts.clientJSON) == "" {
		return opts, errors.New("--client-json is required")
	}
	if opts.timeout <= 0 {
		return opts, errors.New("--timeout must be positive")
	}
	return opts, nil
}

func loadAccount(opts options) (appconfig.Config, account, error) {
	cfg, err := appconfig.Load(firstNonEmpty(opts.configPath, appconfig.DefaultPath()))
	if err != nil {
		return appconfig.Config{}, account{}, fmt.Errorf("load leftpanel config: %w", err)
	}
	for _, configured := range cfg.Email.Accounts {
		if strings.EqualFold(strings.TrimSpace(configured.ID), strings.TrimSpace(opts.accountID)) {
			address := firstNonEmpty(configured.Address, configured.Username, configured.From)
			if address == "" {
				return cfg, account{}, fmt.Errorf("email account %s has no address", opts.accountID)
			}
			if !strings.EqualFold(firstNonEmpty(configured.Provider, "gmail"), "gmail") {
				return cfg, account{}, fmt.Errorf("email account %s is not a Google/Gmail account", opts.accountID)
			}
			return cfg, account{id: strings.TrimSpace(configured.ID), address: address}, nil
		}
	}
	return cfg, account{}, fmt.Errorf("unknown email account %q", opts.accountID)
}

func loadOAuthClient(path string) (string, string, error) {
	data, err := os.ReadFile(strings.TrimSpace(path)) //nolint:gosec // user-provided local OAuth client file.
	if err != nil {
		return "", "", fmt.Errorf("read OAuth client JSON: %w", err)
	}
	var parsed oauthClientFile
	if err := json.Unmarshal(data, &parsed); err != nil {
		return "", "", fmt.Errorf("parse OAuth client JSON: %w", err)
	}
	clientID := firstNonEmpty(parsed.Installed.ClientID, parsed.Web.ClientID, parsed.ClientID)
	clientSecret := firstNonEmpty(parsed.Installed.ClientSecret, parsed.Web.ClientSecret, parsed.ClientSecret)
	if clientID == "" || clientSecret == "" {
		return "", "", errors.New("OAuth client JSON must include client_id and client_secret")
	}
	return clientID, clientSecret, nil
}

func mintToken(ctx context.Context, acct account, clientID, clientSecret string, opts options) (*oauth2.Token, error) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, fmt.Errorf("start OAuth callback listener: %w", err)
	}
	defer listener.Close()

	redirectURL := "http://" + listener.Addr().String() + callbackPath
	config := oauth2.Config{
		ClientID:     clientID,
		ClientSecret: clientSecret,
		RedirectURL:  redirectURL,
		Endpoint:     googleauth.Endpoint,
		Scopes:       googleScopes,
	}

	state, err := randomURLToken(32)
	if err != nil {
		return nil, err
	}
	verifier := oauth2.GenerateVerifier()
	authOptions := []oauth2.AuthCodeOption{
		oauth2.AccessTypeOffline,
		oauth2.S256ChallengeOption(verifier),
		oauth2.SetAuthURLParam("login_hint", acct.address),
	}
	if prompt := strings.TrimSpace(opts.prompt); prompt != "" {
		authOptions = append(authOptions, oauth2.SetAuthURLParam("prompt", prompt))
	}
	authURL := config.AuthCodeURL(state, authOptions...)

	callbacks := make(chan oauthCallback, 1)
	server := &http.Server{Handler: callbackHandler(state, callbacks)}
	defer server.Close()
	go func() {
		if serveErr := server.Serve(listener); serveErr != nil && !errors.Is(serveErr, http.ErrServerClosed) {
			callbacks <- oauthCallback{err: serveErr.Error()}
		}
	}()

	fmt.Fprintln(os.Stderr, "Open this URL in a browser to authorize Google readonly access:")
	fmt.Fprintln(os.Stderr, authURL)
	if opts.open {
		if err := exec.CommandContext(ctx, "xdg-open", authURL).Start(); err != nil {
			return nil, fmt.Errorf("open browser: %w", err)
		}
	}

	var callback oauthCallback
	select {
	case callback = <-callbacks:
	case <-ctx.Done():
		return nil, fmt.Errorf("wait for OAuth callback: %w", ctx.Err())
	}
	if callback.err != "" {
		return nil, errors.New(callback.err)
	}
	if subtle.ConstantTimeCompare([]byte(callback.state), []byte(state)) != 1 {
		return nil, errors.New("OAuth callback state mismatch")
	}
	token, err := config.Exchange(ctx, callback.code, oauth2.VerifierOption(verifier))
	if err != nil {
		return nil, fmt.Errorf("exchange OAuth code: %w", err)
	}
	if err := requireScopes(token, googleScopes); err != nil {
		return nil, err
	}
	return token, nil
}

func callbackHandler(expectedState string, callbacks chan<- oauthCallback) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != callbackPath {
			http.NotFound(w, r)
			return
		}
		query := r.URL.Query()
		callback := oauthCallback{
			code:  query.Get("code"),
			state: query.Get("state"),
			err:   query.Get("error"),
		}
		if callback.err == "" && callback.code == "" {
			callback.err = "OAuth callback did not include a code"
		}
		if callback.err == "" && subtle.ConstantTimeCompare([]byte(callback.state), []byte(expectedState)) != 1 {
			callback.err = "OAuth callback state mismatch"
		}
		select {
		case callbacks <- callback:
		default:
		}
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		if callback.err != "" {
			http.Error(w, "Google authorization failed. You can close this tab.", http.StatusBadRequest)
			return
		}
		fmt.Fprintln(w, "Google authorization complete. You can close this tab.")
	})
}

func verifyGoogleAccount(ctx context.Context, acct account, clientID, clientSecret string, token *oauth2.Token) error {
	config := oauth2.Config{
		ClientID:     clientID,
		ClientSecret: clientSecret,
		Endpoint:     googleauth.Endpoint,
		Scopes:       googleScopes,
	}
	service, err := gmail.NewService(ctx, option.WithHTTPClient(config.Client(ctx, token)))
	if err != nil {
		return fmt.Errorf("create Gmail client: %w", err)
	}
	profile, err := service.Users.GetProfile("me").Do()
	if err != nil {
		return fmt.Errorf("verify Gmail profile: %w", err)
	}
	if !strings.EqualFold(strings.TrimSpace(profile.EmailAddress), acct.address) {
		return fmt.Errorf("authorized account %q does not match configured account %q", profile.EmailAddress, acct.address)
	}
	return nil
}

type calendarSummary struct {
	ID         string         `json:"id"`
	Summary    string         `json:"summary"`
	Primary    bool           `json:"primary"`
	Selected   bool           `json:"selected"`
	Hidden     bool           `json:"hidden"`
	AccessRole string         `json:"accessRole"`
	Upcoming   []eventSummary `json:"upcoming"`
}

type eventSummary struct {
	Summary string `json:"summary"`
	Start   string `json:"start"`
	End     string `json:"end"`
	Status  string `json:"status"`
}

func calendarSummaries(ctx context.Context, service *calendarapi.Service) ([]calendarSummary, error) {
	list, err := service.CalendarList.List().Context(ctx).MaxResults(250).Do()
	if err != nil {
		return nil, err
	}
	out := make([]calendarSummary, 0, len(list.Items))
	now := time.Now().Format(time.RFC3339)
	for _, item := range list.Items {
		if item == nil {
			continue
		}
		summary := calendarSummary{
			ID:         item.Id,
			Summary:    item.Summary,
			Primary:    item.Primary,
			Selected:   item.Selected,
			Hidden:     item.Hidden,
			AccessRole: item.AccessRole,
		}
		events, err := service.Events.List(item.Id).Context(ctx).SingleEvents(true).OrderBy("startTime").TimeMin(now).MaxResults(8).Do()
		if err == nil {
			for _, event := range events.Items {
				if event == nil {
					continue
				}
				summary.Upcoming = append(summary.Upcoming, eventSummary{
					Summary: firstNonEmpty(event.Summary, "(no title)"),
					Start:   eventTime(event.Start),
					End:     eventTime(event.End),
					Status:  event.Status,
				})
			}
		}
		out = append(out, summary)
	}
	return out, nil
}

func eventTime(value *calendarapi.EventDateTime) string {
	if value == nil {
		return ""
	}
	return firstNonEmpty(value.DateTime, value.Date)
}

func requireScopes(token *oauth2.Token, required []string) error {
	rawScope, ok := token.Extra("scope").(string)
	if !ok || strings.TrimSpace(rawScope) == "" {
		return nil
	}
	granted := map[string]bool{}
	for scope := range strings.FieldsSeq(rawScope) {
		granted[scope] = true
	}
	var missing []string
	for _, scope := range required {
		if !granted[scope] {
			missing = append(missing, scope)
		}
	}
	if len(missing) > 0 {
		return fmt.Errorf("OAuth response missing scopes: %s", strings.Join(missing, ", "))
	}
	return nil
}

func defaultClientPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, "Work", "MIT", "timetable", "credentials.json")
}

func randomURLToken(size int) (string, error) {
	data := make([]byte, size)
	if _, err := rand.Read(data); err != nil {
		return "", fmt.Errorf("generate OAuth state: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(data), nil
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if trimmed := strings.TrimSpace(value); trimmed != "" {
			return trimmed
		}
	}
	return ""
}
