// Package secrets centralizes configuration and secret lookup for qs-go.
package secrets

import (
	"errors"
	"strings"
	"sync"

	"github.com/zalando/go-keyring"
)

const DefaultService = "quickshell"

// Resolver is the lookup boundary for values stored in Secret Service.
type Resolver interface {
	Lookup(key string) (string, bool)
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

func NewResolver() Resolver {
	resolverMu.RLock()
	factory := resolverFactory
	resolverMu.RUnlock()
	return factory()
}

func NewKeyringResolver(service string) Resolver {
	service = strings.TrimSpace(service)
	if service == "" {
		service = DefaultService
	}
	return keyringResolver{service: service}
}

func NewMapResolver(values map[string]string) Resolver {
	copyValues := make(map[string]string, len(values))
	for key, value := range values {
		copyValues[key] = value
	}
	return mapResolver{values: copyValues}
}

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

func (r mapResolver) Lookup(key string) (string, bool) {
	value, ok := r.values[key]
	return value, ok
}

func Set(key, value string) error {
	key = strings.TrimSpace(key)
	if key == "" {
		return errors.New("secret key is required")
	}
	return keyring.Set(DefaultService, key, value)
}

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

func IsNotFound(err error) bool {
	return errors.Is(err, keyring.ErrNotFound)
}
