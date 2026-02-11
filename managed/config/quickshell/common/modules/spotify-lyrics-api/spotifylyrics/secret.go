package spotifylyrics

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

const defaultSecretDictURL = "https://github.com/xyloflake/spot-secrets-go/blob/main/secrets/secretDict.json?raw=true"

type secretDict map[string][]int

type secretCache struct {
	ETag    string `json:"etag"`
	Body    []byte `json:"body"`
	SavedAt int64  `json:"savedAt"`
}

type secretDictEntry struct {
	Version string
	Encoded []int
}

func decodeSecretDictOrdered(body []byte) ([]secretDictEntry, error) {
	dec := json.NewDecoder(bytes.NewReader(body))
	tok, err := dec.Token()
	if err != nil {
		return nil, err
	}
	if d, ok := tok.(json.Delim); !ok || d != '{' {
		return nil, fmt.Errorf("secretDict.json: expected object")
	}

	var out []secretDictEntry
	for dec.More() {
		kTok, err := dec.Token()
		if err != nil {
			return nil, err
		}
		k, ok := kTok.(string)
		if !ok || k == "" {
			return nil, fmt.Errorf("secretDict.json: invalid key")
		}
		var encoded []int
		if err := dec.Decode(&encoded); err != nil {
			return nil, err
		}
		out = append(out, secretDictEntry{Version: k, Encoded: encoded})
	}

	// Consume closing '}'
	if _, err := dec.Token(); err != nil {
		return nil, err
	}
	return out, nil
}

func readSecretCache(path string) (*secretCache, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var sc secretCache
	if err := json.Unmarshal(b, &sc); err != nil {
		return nil, err
	}
	if len(sc.Body) == 0 {
		return nil, fmt.Errorf("secret cache body is empty")
	}
	return &sc, nil
}

func writeSecretCache(path string, etag string, body []byte) error {
	sc := secretCache{
		ETag:    etag,
		Body:    body,
		SavedAt: time.Now().Unix(),
	}
	b, err := json.Marshal(sc)
	if err != nil {
		return err
	}
	return writeFileAtomic(path, b, 0o600)
}

func fetchLatestSecret(ctx context.Context, hc *http.Client, url string, cachePath string) (secret string, version string, _ error) {
	if hc == nil {
		return "", "", fmt.Errorf("http client is nil")
	}

	var cached *secretCache
	if cachePath != "" {
		if sc, err := readSecretCache(cachePath); err == nil {
			cached = sc
		}
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "", "", err
	}
	if cached != nil && cached.ETag != "" {
		req.Header.Set("If-None-Match", cached.ETag)
	}
	resp, err := hc.Do(req)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()

	var body []byte
	switch {
	case resp.StatusCode == http.StatusNotModified:
		if cached == nil {
			return "", "", fmt.Errorf("secretDict 304 but no cache available")
		}
		body = cached.Body
	case resp.StatusCode >= 400:
		return "", "", &Error{Status: resp.StatusCode, Message: "failed to fetch secretDict.json"}
	default:
		body, err = io.ReadAll(resp.Body)
		if err != nil {
			return "", "", err
		}
		if cachePath != "" {
			// Best-effort cache write.
			_ = writeSecretCache(cachePath, resp.Header.Get("ETag"), body)
		}
	}

	entries, err := decodeSecretDictOrdered(body)
	if err != nil {
		return "", "", fmt.Errorf("invalid secretDict.json: %w", err)
	}
	if len(entries) == 0 {
		return "", "", fmt.Errorf("secretDict.json was empty")
	}

	// Upstream PHP uses array_key_last(json_decode(..., true)), which effectively
	// selects the last key in the JSON object order.
	latest := entries[len(entries)-1]
	if latest.Version == "" {
		return "", "", fmt.Errorf("secretDict.json: last key was empty")
	}
	if len(latest.Encoded) == 0 {
		return "", "", fmt.Errorf("secret for version %s was empty", latest.Version)
	}
	// Match upstream PHP logic:
	// - XOR-decode ints
	// - then implode() them with "" separator, which produces a decimal string
	//   (e.g., [65,66] => "6566"), not a byte string.
	var bld strings.Builder
	for i, ch := range latest.Encoded {
		decoded := ch ^ ((i % 33) + 9)
		bld.WriteString(fmt.Sprintf("%d", decoded))
	}
	return bld.String(), latest.Version, nil
}
