package todoist

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	apiSync "github.com/CnTeng/todoist-api-go/sync"
)

const todoistCacheVersion = 1

type cacheState struct {
	SyncToken string                      `json:"sync_token"`
	Tasks     map[string]*apiSync.Task    `json:"tasks"`
	Projects  map[string]*apiSync.Project `json:"projects"`
}

type cacheEnvelope struct {
	Version int        `json:"version"`
	SavedAt int64      `json:"saved_at"`
	State   cacheState `json:"state"`
}

func readCacheState(cachePath string) (*cacheState, error) {
	cachePath = strings.TrimSpace(cachePath)
	if cachePath == "" {
		return nil, fmt.Errorf("empty cache path")
	}

	b, err := os.ReadFile(cachePath)
	if err != nil {
		return nil, err
	}

	var env cacheEnvelope
	if err := json.Unmarshal(b, &env); err != nil {
		return nil, err
	}
	if env.Version != todoistCacheVersion {
		return nil, fmt.Errorf("cache version mismatch")
	}

	if env.State.Tasks == nil {
		env.State.Tasks = map[string]*apiSync.Task{}
	}
	if env.State.Projects == nil {
		env.State.Projects = map[string]*apiSync.Project{}
	}
	return &env.State, nil
}

func writeCacheState(cachePath string, state *cacheState) error {
	cachePath = strings.TrimSpace(cachePath)
	if cachePath == "" || state == nil {
		return nil
	}

	if state.Tasks == nil {
		state.Tasks = map[string]*apiSync.Task{}
	}
	if state.Projects == nil {
		state.Projects = map[string]*apiSync.Project{}
	}

	env := cacheEnvelope{
		Version: todoistCacheVersion,
		SavedAt: time.Now().Unix(),
		State:   *state,
	}
	b, err := json.Marshal(env)
	if err != nil {
		return err
	}
	return writeFileAtomic(cachePath, b, 0o600)
}

func writeFileAtomic(path string, data []byte, perm os.FileMode) error {
	if path == "" {
		return fmt.Errorf("empty path")
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}

	tmp, err := os.CreateTemp(dir, ".tmp-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer func() {
		_ = os.Remove(tmpName)
	}()

	if err := tmp.Chmod(perm); err != nil {
		_ = tmp.Close()
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmpName, path)
}
