// Package todoist wraps the Todoist REST API using todoist-api-go.
package todoist

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"time"

	apiSync "github.com/CnTeng/todoist-api-go/sync"
	"github.com/CnTeng/todoist-api-go/todoist"
	"github.com/joho/godotenv"
	"os"
)

type taskOutput struct {
	ID       string  `json:"id"`
	Title    string  `json:"title"`
	Notes    string  `json:"notes,omitempty"`
	Due      *int64  `json:"due,omitempty"`
	DueHuman *string `json:"due_human,omitempty"`
	Updated  int64   `json:"updated"`
}

type listOutput struct {
	Today       []taskOutput            `json:"today"`
	Projects    map[string][]taskOutput `json:"projects"`
	LastUpdated string                  `json:"last_updated"`
}

func readToken(envFile string) (string, error) {
	if envFile != "" {
		if env, err := godotenv.Read(envFile); err == nil {
			if t := strings.TrimSpace(env["TODOIST_API_TOKEN"]); t != "" {
				return t, nil
			}
		}
	}
	if t := strings.TrimSpace(os.Getenv("TODOIST_API_TOKEN")); t != "" {
		return t, nil
	}
	return "", fmt.Errorf("TODOIST_API_TOKEN not found in environment (.env)")
}

func makeClient(token string) *todoist.Client {
	return todoist.NewClient(http.DefaultClient, token, todoist.DefaultHandler)
}

// ListTasks fetches all tasks and returns JSON.
func ListTasks(envFile string) string {
	token, err := readToken(envFile)
	if err != nil {
		b, _ := json.Marshal(map[string]string{"error": err.Error()})
		return string(b)
	}

	client := makeClient(token)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	syncToken := apiSync.DefaultSyncToken
	resourceTypes := apiSync.ResourceTypes{apiSync.Tasks, apiSync.Projects}
	resp, err := client.Sync(ctx, &apiSync.SyncRequest{
		SyncToken:     &syncToken,
		ResourceTypes: &resourceTypes,
	})
	if err != nil {
		b, _ := json.Marshal(map[string]string{"error": err.Error()})
		return string(b)
	}

	projectNames := map[string]string{}
	for _, p := range resp.Projects {
		if p == nil || p.IsDeleted || p.IsArchived {
			continue
		}
		projectNames[p.ID] = p.Name
	}

	today := time.Now().In(time.Local)
	todayDate := dateOnly(today)

	out := listOutput{
		Today:    make([]taskOutput, 0),
		Projects: map[string][]taskOutput{},
	}
	var latestUpdate time.Time

	for _, task := range resp.Tasks {
		if task == nil || task.Checked || task.IsDeleted {
			continue
		}
		if task.UpdatedAt.After(latestUpdate) {
			latestUpdate = task.UpdatedAt
		}
		item := taskOutput{
			ID:      task.ID,
			Title:   task.Content,
			Notes:   task.Description,
			Updated: task.UpdatedAt.Unix(),
		}
		dueTs, dueHuman, isToday := taskDue(task, todayDate)
		if dueTs != nil {
			item.Due = dueTs
			item.DueHuman = dueHuman
		}
		if isToday {
			out.Today = append(out.Today, item)
			continue
		}
		projName := projectNames[task.ProjectID]
		if projName == "" {
			projName = "Unknown"
		}
		out.Projects[projName] = append(out.Projects[projName], item)
	}

	if latestUpdate.IsZero() {
		latestUpdate = time.Now().UTC()
	}
	out.LastUpdated = latestUpdate.UTC().Format(time.RFC3339)

	sort.Slice(out.Today, func(i, j int) bool { return out.Today[i].Title < out.Today[j].Title })
	for k := range out.Projects {
		p := out.Projects[k]
		sort.Slice(p, func(i, j int) bool { return p[i].Title < p[j].Title })
		out.Projects[k] = p
	}

	b, _ := json.Marshal(out)
	return string(b)
}

// Action executes a task action (close/delete/add/update) and returns JSON.
// verb: "close" | "delete" | "add" | "update"
// argsJSON: JSON object with action-specific fields.
func Action(envFile, verb, argsJSON string) string {
	token, err := readToken(envFile)
	if err != nil {
		b, _ := json.Marshal(map[string]string{"error": err.Error()})
		return string(b)
	}

	client := makeClient(token)
	taskService := todoist.NewTaskService(client)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	var args map[string]string
	_ = json.Unmarshal([]byte(argsJSON), &args)

	switch verb {
	case "close":
		id := args["id"]
		if id == "" {
			b, _ := json.Marshal(map[string]string{"error": "id is required"})
			return string(b)
		}
		_, err = taskService.CloseTask(ctx, &apiSync.TaskCloseArgs{ID: id})
	case "delete":
		id := args["id"]
		if id == "" {
			b, _ := json.Marshal(map[string]string{"error": "id is required"})
			return string(b)
		}
		_, err = taskService.DeleteTask(ctx, &apiSync.TaskDeleteArgs{ID: id})
	case "add":
		content := args["content"]
		if content == "" {
			b, _ := json.Marshal(map[string]string{"error": "content is required"})
			return string(b)
		}
		addArgs := &apiSync.TaskAddArgs{Content: content}
		if desc := args["description"]; desc != "" {
			addArgs.Description = &desc
		}
		if projID := args["project_id"]; projID != "" {
			addArgs.ProjectID = &projID
		}
		if due := args["due_string"]; due != "" {
			addArgs.Due = &apiSync.Due{String: &due}
		}
		_, err = taskService.AddTask(ctx, addArgs)
	case "update":
		id := args["id"]
		if id == "" {
			b, _ := json.Marshal(map[string]string{"error": "id is required"})
			return string(b)
		}
		updateArgs := &apiSync.TaskUpdateArgs{ID: id}
		if content := args["content"]; content != "" {
			updateArgs.Content = &content
		}
		if desc := args["description"]; desc != "" {
			updateArgs.Description = &desc
		}
		if due := args["due_string"]; due != "" {
			updateArgs.Due = &apiSync.Due{String: &due}
		}
		_, err = taskService.UpdateTask(ctx, updateArgs)
	default:
		b, _ := json.Marshal(map[string]string{"error": "unknown verb: " + verb})
		return string(b)
	}

	if err != nil {
		b, _ := json.Marshal(map[string]string{"error": err.Error()})
		return string(b)
	}
	b, _ := json.Marshal(map[string]bool{"ok": true})
	return string(b)
}

func taskDue(task *apiSync.Task, todayDate string) (*int64, *string, bool) {
	if task.Due == nil || task.Due.Date == nil {
		return nil, nil, false
	}
	dueAt := task.Due.Date.In(time.Local)
	dueUnix := dueAt.Unix()
	dueDate := dateOnly(dueAt)
	hasTime := dueAt.Hour() != 0 || dueAt.Minute() != 0 || dueAt.Second() != 0

	if dueDate > todayDate {
		return &dueUnix, nil, false
	}

	var label string
	if dueDate < todayDate {
		label = "Overdue"
	} else if hasTime {
		label = "Today " + dueAt.Format("3:04 PM")
	} else {
		label = "Today"
	}
	return &dueUnix, &label, true
}

func dateOnly(t time.Time) string {
	y, m, d := t.Date()
	return fmt.Sprintf("%04d-%02d-%02d", y, int(m), d)
}
