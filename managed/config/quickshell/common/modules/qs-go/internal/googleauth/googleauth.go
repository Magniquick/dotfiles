// Package googleauth owns refreshable Google OAuth clients shared by qs-go features.
package googleauth

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"golang.org/x/oauth2"

	"qs-go/internal/secrets"
)

// Endpoint is Google's OAuth 2.0 endpoint.
var Endpoint = oauth2.Endpoint{
	AuthURL:  "https://accounts.google.com/o/oauth2/auth",
	TokenURL: "https://oauth2.googleapis.com/token",
}

// Account contains the secret material needed to refresh Google OAuth tokens.
type Account struct {
	ID              string
	Address         string
	TokenJSON       string
	ClientID        string
	ClientSecret    string
	TokenKey        string
	ClientIDKey     string
	ClientSecretKey string
}

// EnvID returns the environment/Secret Service-safe account id.
func EnvID(id string) string {
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

// KeyPrefix returns the shared Google secret prefix for an account id.
func KeyPrefix(id string) string {
	return "GOOGLE_" + EnvID(id) + "_"
}

// AccountFromResolver loads shared Google OAuth secrets for an account id.
func AccountFromResolver(id, address string, resolver secrets.Resolver) Account {
	account := Account{ID: strings.TrimSpace(id), Address: strings.TrimSpace(address)}
	prefix := KeyPrefix(id)
	account.TokenKey = prefix + "TOKEN_JSON"
	account.ClientIDKey = prefix + "CLIENT_ID"
	account.ClientSecretKey = prefix + "CLIENT_SECRET"
	if resolver == nil {
		return account
	}
	account.TokenJSON, _ = resolver.Lookup(account.TokenKey)
	account.ClientID, _ = resolver.Lookup(account.ClientIDKey)
	account.ClientSecret, _ = resolver.Lookup(account.ClientSecretKey)
	return account
}

// NewHTTPClient returns an OAuth HTTP client that refreshes and persists tokens.
func NewHTTPClient(ctx context.Context, account Account, scopes []string) (*http.Client, error) {
	token, err := RefreshableToken(account)
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(account.ClientID) == "" || strings.TrimSpace(account.ClientSecret) == "" {
		return nil, fmt.Errorf("account %s Google OAuth refresh requires %s and %s", account.ID, firstNonEmpty(account.ClientIDKey, KeyPrefix(account.ID)+"CLIENT_ID"), firstNonEmpty(account.ClientSecretKey, KeyPrefix(account.ID)+"CLIENT_SECRET"))
	}
	store := secrets.NewStore()
	if store == nil {
		return nil, fmt.Errorf("account %s Google OAuth refresh requires a writable Secret Service store", account.ID)
	}
	config := oauth2.Config{
		ClientID:     strings.TrimSpace(account.ClientID),
		ClientSecret: strings.TrimSpace(account.ClientSecret),
		Endpoint:     Endpoint,
		Scopes:       scopes,
	}
	source := config.TokenSource(ctx, token)
	source = oauth2.ReuseTokenSource(token, source)
	source = &persistTokenSource{
		accountID:     account.ID,
		tokenKey:      firstNonEmpty(account.TokenKey, KeyPrefix(account.ID)+"TOKEN_JSON"),
		refreshToken:  token.RefreshToken,
		store:         store,
		source:        source,
		lastPersisted: token,
	}
	return oauth2.NewClient(ctx, source), nil
}

// RefreshableToken parses a token JSON value and requires a refresh token.
func RefreshableToken(account Account) (*oauth2.Token, error) {
	token, err := Token(account)
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(token.RefreshToken) == "" {
		return nil, fmt.Errorf("account %s Google OAuth token must include refresh_token; re-run Google OAuth provisioning", account.ID)
	}
	if token.Expiry.IsZero() || strings.TrimSpace(token.AccessToken) == "" {
		token.Expiry = time.Now().Add(-time.Minute)
	}
	return token, nil
}

// Token parses a stored OAuth token JSON value.
func Token(account Account) (*oauth2.Token, error) {
	raw := strings.TrimSpace(account.TokenJSON)
	if raw == "" {
		return nil, fmt.Errorf("account %s has no Google OAuth token; set %s", account.ID, firstNonEmpty(account.TokenKey, KeyPrefix(account.ID)+"TOKEN_JSON"))
	}
	var token oauth2.Token
	if err := json.Unmarshal([]byte(raw), &token); err != nil {
		return nil, fmt.Errorf("account %s has invalid Google OAuth token JSON: %w", account.ID, err)
	}
	if strings.TrimSpace(token.TokenType) == "" {
		token.TokenType = "Bearer"
	}
	if strings.TrimSpace(token.AccessToken) == "" {
		return nil, fmt.Errorf("account %s Google OAuth token JSON has no access_token", account.ID)
	}
	return &token, nil
}

// StoreCredentials writes a shared Google OAuth credential set.
func StoreCredentials(store secrets.Store, id string, token *oauth2.Token, clientID, clientSecret string) error {
	if store == nil {
		return errors.New("Secret Service store is not writable")
	}
	raw, err := json.Marshal(token)
	if err != nil {
		return fmt.Errorf("serialize OAuth token: %w", err)
	}
	prefix := KeyPrefix(id)
	for key, value := range map[string]string{
		prefix + "TOKEN_JSON":    string(raw),
		prefix + "CLIENT_ID":     strings.TrimSpace(clientID),
		prefix + "CLIENT_SECRET": strings.TrimSpace(clientSecret),
	} {
		if strings.TrimSpace(value) == "" {
			return fmt.Errorf("%s is required", key)
		}
		if err := store.Set(key, value); err != nil {
			return fmt.Errorf("store %s: %w", key, err)
		}
	}
	return nil
}

type persistTokenSource struct {
	accountID     string
	tokenKey      string
	refreshToken  string
	store         secrets.Store
	source        oauth2.TokenSource
	lastPersisted *oauth2.Token
}

func (s *persistTokenSource) Token() (*oauth2.Token, error) {
	token, err := s.source.Token()
	if err != nil {
		return nil, err
	}
	if token == nil {
		return nil, fmt.Errorf("account %s Google OAuth refresh returned no token", s.accountID)
	}
	if strings.TrimSpace(token.RefreshToken) == "" {
		token.RefreshToken = s.refreshToken
	}
	if !tokenChanged(s.lastPersisted, token) {
		return token, nil
	}
	raw, err := json.Marshal(token)
	if err != nil {
		return nil, fmt.Errorf("account %s Google OAuth token marshal failed: %w", s.accountID, err)
	}
	if err := s.store.Set(s.tokenKey, string(raw)); err != nil {
		return nil, fmt.Errorf("account %s Google OAuth token persist failed: %w", s.accountID, err)
	}
	s.lastPersisted = token
	return token, nil
}

func tokenChanged(previous, current *oauth2.Token) bool {
	if previous == nil || current == nil {
		return previous != current
	}
	return previous.AccessToken != current.AccessToken ||
		previous.RefreshToken != current.RefreshToken ||
		previous.TokenType != current.TokenType ||
		!previous.Expiry.Equal(current.Expiry)
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if trimmed := strings.TrimSpace(value); trimmed != "" {
			return trimmed
		}
	}
	return ""
}
