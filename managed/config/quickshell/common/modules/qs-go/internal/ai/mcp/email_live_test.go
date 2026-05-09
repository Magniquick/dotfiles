//go:build liveemail

package mcp

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	"qs-go/internal/ai/shared"
	"qs-go/internal/secrets"
)

func TestLiveEmailReadAccess(t *testing.T) {
	cleanup := secrets.UseResolverForTest(secrets.NewKeyringResolver(secrets.DefaultService))
	defer cleanup()

	result, err := CallTool(`[]`, "", "email_accounts", map[string]any{})
	if err != nil {
		t.Fatalf("email_accounts error: %v", err)
	}
	if result.IsError {
		t.Fatalf("email_accounts failed: %s", result.Text)
	}

	accountsRaw, ok := result.Data["accounts"].([]map[string]any)
	if !ok || len(accountsRaw) == 0 {
		raw, _ := json.Marshal(result.Data)
		t.Fatalf("email_accounts returned no accounts: %s", raw)
	}

	for _, account := range accountsRaw {
		id := strings.TrimSpace(fmt.Sprint(account["id"]))
		if id == "" {
			t.Fatalf("account without id: %#v", account)
		}
		search := liveSearchAccount(t, id)
		if search.IsError {
			t.Fatalf("email_search failed for %s: %s", id, search.Text)
		}
		for _, query := range []string{
			"label:INBOX after:2000/01/01 is:read",
			"label:INBOX after:2000/01/01 has:attachment",
		} {
			search = liveSearchAccountQuery(t, id, query)
			if search.IsError {
				t.Fatalf("email_search query %q failed for %s: %s", query, id, search.Text)
			}
			t.Logf("email_search account=%s query=%q matched=%v returned=%v limit=%v", id, query, search.Data["matched_count"], search.Data["returned_count"], search.Data["limit"])
		}
	}
}

func liveSearchAccount(t *testing.T, account string) shared.ToolResult {
	t.Helper()
	result, err := CallTool(`[]`, "", "email_search", map[string]any{
		"account": account,
		"mailbox": "INBOX",
		"limit":   1,
	})
	if err != nil {
		t.Fatalf("email_search error for %s: %v", account, err)
	}
	return result
}

func liveSearchAccountQuery(t *testing.T, account string, query string) shared.ToolResult {
	t.Helper()
	result, err := CallTool(`[]`, "", "email_search", map[string]any{
		"account": account,
		"query":   query,
		"limit":   50,
	})
	if err != nil {
		t.Fatalf("email_search query %q error for %s: %v", query, account, err)
	}
	return result
}
