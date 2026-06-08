// Package secrets centralizes configuration and secret lookup for qs-go.
package secrets

import (
	"errors"
	"maps"
	"strings"
	"sync"

	"github.com/zalando/go-keyring"
)

// DefaultService is the Secret Service namespace used by qs-go.
const DefaultService = "quickshell"

// Resolver is the lookup boundary for values stored in Secret Service.
type Resolver interface {
	Lookup(key string) (string, bool)
}

// Store is a resolver that can also persist updated secret values.
type Store interface {
	Resolver
	Set(key, value string) error
}

type keyringResolver struct {
	service string
}

type mapResolver struct {
	values map[string]string
}

var (
	resolverMu      sync.RWMutex
	resolverFactory = func() Resolver {
		return NewKeyringResolver(DefaultService)
	}
)

// NewResolver returns the current process-wide secret resolver.
func NewResolver() Resolver {
	resolverMu.RLock()
	factory := resolverFactory
	resolverMu.RUnlock()
	return factory()
}

// NewStore returns the current process-wide secret store when it supports writes.
func NewStore() Store {
	resolver := NewResolver()
	store, _ := resolver.(Store)
	return store
}

// NewKeyringResolver returns a Secret Service-backed resolver.
func NewKeyringResolver(service string) Resolver {
	service = strings.TrimSpace(service)
	if service == "" {
		service = DefaultService
	}
	return keyringResolver{service: service}
}

// NewMapResolver returns an in-memory resolver for tests.
func NewMapResolver(values map[string]string) Resolver {
	return NewMapStore(values)
}

// NewMapStore returns an in-memory writable secret store for tests.
func NewMapStore(values map[string]string) Store {
	copyValues := make(map[string]string, len(values))
	maps.Copy(copyValues, values)
	return mapResolver{values: copyValues}
}

// UseResolverForTest replaces the resolver factory for a test.
func UseResolverForTest(resolver Resolver) func() {
	resolverMu.Lock()
	previous := resolverFactory
	resolverFactory = func() Resolver { return resolver }
	resolverMu.Unlock()
	return func() {
		resolverMu.Lock()
		resolverFactory = previous
		resolverMu.Unlock()
	}
}

func (r keyringResolver) Lookup(key string) (string, bool) {
	key = strings.TrimSpace(key)
	if key == "" {
		return "", false
	}
	value, err := keyring.Get(r.service, key)
	if err != nil {
		return "", false
	}
	return value, true
}

func (r keyringResolver) Set(key, value string) error {
	key = strings.TrimSpace(key)
	if key == "" {
		return errors.New("secret key is required")
	}
	return keyring.Set(r.service, key, value)
}

func (r mapResolver) Lookup(key string) (string, bool) {
	value, ok := r.values[key]
	return value, ok
}

func (r mapResolver) Set(key, value string) error {
	key = strings.TrimSpace(key)
	if key == "" {
		return errors.New("secret key is required")
	}
	r.values[key] = value
	return nil
}

// Set writes a secret under the default service.
func Set(key, value string) error {
	key = strings.TrimSpace(key)
	if key == "" {
		return errors.New("secret key is required")
	}
	return keyring.Set(DefaultService, key, value)
}

// Delete removes a secret under the default service.
func Delete(key string) error {
	key = strings.TrimSpace(key)
	if key == "" {
		return errors.New("secret key is required")
	}
	err := keyring.Delete(DefaultService, key)
	if errors.Is(err, keyring.ErrNotFound) {
		return nil
	}
	return err
}

// IsNotFound reports whether an error means the secret was absent.
func IsNotFound(err error) bool {
	return errors.Is(err, keyring.ErrNotFound)
}
