package secrets

import "testing"

func TestMapResolverLookupCopiesInput(t *testing.T) {
	values := map[string]string{"TOKEN": "secret-token"}
	resolver := NewMapResolver(map[string]string{
		"TOKEN": values["TOKEN"],
	})
	values["TOKEN"] = "mutated"

	if got, ok := resolver.Lookup("TOKEN"); !ok || got != "secret-token" {
		t.Fatalf("resolver was mutated through input map, got %q ok=%v", got, ok)
	}
}
