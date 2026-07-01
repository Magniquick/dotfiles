#!/usr/bin/env bash
# ── Layer 2: normalize + Layer 3: sink ────────────────────────────────────
# Reads the enriched blob from Layer 1 (report.sh) on stdin and maps each
# agent's native event vocabulary onto ONE shared status vocabulary, then
# records the normalized state.
#
# Shared status vocabulary:
#   active         — working a turn (prompt accepted, tool running, thinking)
#   idle           — turn finished / session waiting for the user
#   waiting-input  — blocked on the user (permission / question)
#   waiting-on-bg  — turn ended but a backgrounded task is still alive
#   ended          — session closed
#
# Layer 3 sink for now: a normalized JSONL log + a per-session current-state
# file. Emitting native Quickshell IPC events is deferred (see emit_qs()).
#
# Never fail the calling hook: always exit 0.

HERE="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/quickshell-agents"
NORM_LOG="$STATE_DIR/status.jsonl"
mkdir -p "$STATE_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0

blob="$(cat 2>/dev/null)"
[ -z "$blob" ] && exit 0
g() { printf '%s' "$blob" | jq -r "$1" 2>/dev/null; }

tool="$(g '.tool')"
event="$(g '.event')"
ts="$(g '.ts')"
# cwd: claude/codex use .cwd; antigravity uses .workspacePaths[]
cwd="$(g '.raw.cwd // (.raw.workspacePaths[0]?) // .hook_cwd // empty')"
workspace="$(g '.window.workspace.name // empty')"
term_pid="$(g '.window.pid // empty')"
window_address="$(g '.window.address // empty')"
# tool name: claude/codex use .tool_name; antigravity nests it in .toolCall
tool_name="$(g '.raw.tool_name // .raw.toolCall.name // .raw.toolCall.toolName // empty')"

# The kitty tab hosting this agent = the shell whose parent IS the terminal
# window process. That shell's pid is what `kitty @ --match pid:` targets.
tab_shell_pid="$(printf '%s' "$blob" | jq -r \
  '(.window.pid) as $k | first(.proc_chain[] | select(.ppid == $k) | .pid) // empty' 2>/dev/null)"

# session id across agents: claude/codex=.session_id, antigravity=.conversationId,
# codex notify=.thread-id
session_id="$(g '.raw.session_id // .raw.conversationId // .raw.conversation_id // .raw."thread-id" // .raw.thread_id // empty')"
[ -z "$session_id" ] && session_id="${tool}-$(g '.hook_ppid')"
skey="$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9._-' '_')"
BGPIDS_FILE="$STATE_DIR/${skey}.bgpids"
STATE_FILE="$STATE_DIR/${skey}.json"

# --- background-task bookkeeping -------------------------------------------
# Agents don't expose the OS pid of a backgrounded command (Claude gives a
# `backgroundTaskId`, not a pid). But the command runs as a DESCENDANT of the
# agent process, so we track its command string and, at turn end, ask "is that
# command still alive under the agent?" — the user's "see if command exists".
#
# Tracker line format:  <taskId>\t<base64(command)>
agent_pid_now() {
  printf '%s' "$blob" | jq -r \
    '.proc_chain | map(select(.comm | test("^(claude|codex|gemini|antigravity|agy|node)$"; "i"))) | .[0].pid // empty' 2>/dev/null
}

is_bg_bash() {
  local v; v="$(g '(.raw.tool_input.run_in_background // .raw.tool_input.runInBackground // false)')"
  [ "$v" = "true" ]
}

record_bg_task() {
  local id cmd b64
  id="$(g '(.raw.tool_response.backgroundTaskId // .raw.tool_response.background_task_id // empty)')"
  cmd="$(g '.raw.tool_input.command // empty')"
  [ -z "$cmd" ] && return
  b64="$(printf '%s' "$cmd" | base64 -w0 2>/dev/null)"
  # de-dupe by taskId (PostToolUse can repeat)
  [ -f "$BGPIDS_FILE" ] && grep -q "^${id}	" "$BGPIDS_FILE" 2>/dev/null && return
  printf '%s\t%s\n' "${id:-?}" "$b64" >>"$BGPIDS_FILE"
}

# all descendant pids of $1 (recursive), one per line
descendants() {
  local kid
  for kid in $(pgrep -P "$1" 2>/dev/null); do
    printf '%s\n' "$kid"; descendants "$kid"
  done
}

# is $1 (command substring) running among descendants of $2 (agent pid)?
cmd_alive() {
  local cmd="$1" root="$2" d cl
  [ -z "$root" ] && return 1
  for d in $(descendants "$root"); do
    cl="$(tr '\0' ' ' <"/proc/$d/cmdline" 2>/dev/null)"
    case "$cl" in *"$cmd"*) return 0 ;; esac
  done
  return 1
}

live_bg_count() {
  [ -f "$BGPIDS_FILE" ] || { printf 0; return; }
  local root live=0 keep="" line b64 cmd
  root="$(agent_pid_now)"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    b64="${line#*	}"
    cmd="$(printf '%s' "$b64" | base64 -d 2>/dev/null)"
    if [ -n "$cmd" ] && cmd_alive "$cmd" "$root"; then
      live=$((live + 1)); keep="$keep$line"$'\n'
    fi
  done <"$BGPIDS_FILE"
  printf '%s' "$keep" >"$BGPIDS_FILE"
  printf '%s' "$live"
}

# --- native event  →  shared status ---------------------------------------
state="unknown"
case "$tool" in
  claude | codex)
    case "$event" in
      SessionStart)               state="idle" ;;
      UserPromptSubmit)           state="active" ;;
      PreToolUse)                 state="active" ;;
      PostToolUse)
        state="active"
        [ "$tool_name" = "Bash" ] && is_bg_bash && record_bg_task ;;
      Notification)
        [ "$(g '.raw.notification_type // empty')" = "idle_prompt" ] \
          && state="idle" || state="waiting-input" ;;
      PermissionRequest)          state="waiting-input" ;;   # codex
      Stop | SubagentStop)
        [ "$(live_bg_count)" -gt 0 ] && state="waiting-on-bg" || state="idle" ;;
      SessionEnd)                 state="ended" ;;
    esac
    ;;
  gemini)   # Gemini CLI vocabulary (~/.gemini/settings.json)
    case "$event" in
      SessionStart)               state="idle" ;;
      BeforeAgent)                state="active" ;;
      BeforeTool | AfterTool | BeforeModel | AfterModel) state="active" ;;
      AfterAgent)
        [ "$(live_bg_count)" -gt 0 ] && state="waiting-on-bg" || state="idle" ;;
      Notification)               state="waiting-input" ;;
      SessionEnd)                 state="ended" ;;
    esac
    ;;
  antigravity)   # Antigravity CLI (agy) vocabulary
    case "$event" in
      PreInvocation)              state="active" ;;
      PreToolUse | PostToolUse)   state="active" ;;
      PostInvocation | Stop)
        [ "$(live_bg_count)" -gt 0 ] && state="waiting-on-bg" || state="idle" ;;
    esac
    ;;
esac

# --- Layer 3 sink ----------------------------------------------------------
bg_count="$(live_bg_count)"

record="$(jq -nc \
  --arg id "$session_id" --arg tool "$tool" --arg state "$state" \
  --arg event "$event" --arg ws "$workspace" --arg cwd "$cwd" \
  --arg tool_name "$tool_name" --arg tpid "$term_pid" \
  --arg waddr "$window_address" --arg tabpid "$tab_shell_pid" \
  --argjson bg "${bg_count:-0}" --argjson ts "${ts:-0}" \
  '{id:$id, tool:$tool, state:$state, event:$event, workspace:$ws,
    cwd:$cwd, tool_name:$tool_name, term_pid:$tpid,
    window_address:$waddr, tab_shell_pid:$tabpid, bg_count:$bg, ts:$ts}')"

# normalized append-log (human/agent debugging)
printf '%s\n' "$record" >>"$NORM_LOG" 2>/dev/null

# previous state, to fire notifications only on transitions
prev_state=""
[ -f "$STATE_FILE" ] && prev_state="$(jq -r '.state // empty' "$STATE_FILE" 2>/dev/null)"

# per-session current state (this is what the QS consumer will read/receive)
if [ "$state" = "ended" ]; then
  rm -f "$STATE_FILE" "$BGPIDS_FILE" 2>/dev/null
else
  printf '%s\n' "$record" >"$STATE_FILE" 2>/dev/null
fi

# Notify on entering an attention state (not every active tick). Clean title =
# agent name (matchable app-name for the user's shell matcher), reason in body;
# no emoji, no workspace clutter. We are the single notifier for every agent —
# the agents' own duplicate notifiers are disabled (e.g. Codex notify.sh).
notify_transition() {
  [ "$state" = "$prev_state" ] && return

  local app title reason
  case "$tool" in
    claude)      app="Claude Code";  title="Claude Code" ;;
    codex)       app="openai-codex"; title="Codex" ;;
    antigravity) app="Antigravity";  title="Antigravity" ;;
    *)           app="$tool";        title="$tool" ;;
  esac
  case "$state" in
    waiting-input)  reason="Needs your input" ;;
    waiting-on-bg)  reason="Waiting on a background task" ;;
    idle)           reason="Finished its turn" ;;
    *) return ;;
  esac
  setsid -f "$HERE/notify.sh" "$session_id" "$app" "$title" "$reason" >/dev/null 2>&1 \
    || ( "$HERE/notify.sh" "$session_id" "$app" "$title" "$reason" >/dev/null 2>&1 & )
}
notify_transition

emit_qs() {
  : # TODO(quickshell): qs ipc call agents report "$record"  — native QS events, later.
}
emit_qs

exit 0
