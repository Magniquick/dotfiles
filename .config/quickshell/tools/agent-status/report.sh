#!/usr/bin/env bash
# ── Layer 1: raw capture ──────────────────────────────────────────────────
# Invoked directly by an agent's hook. Its only job is to gather EVERYTHING
# we can possibly observe about this hook event, dump it to a raw log (so we
# can discover each agent's payload shape), then hand the enriched blob to
# Layer 2 (normalize.sh) on stdin.
#
# Usage (from the hook config):  report.sh <tool> <native-event>
#   tool          : claude | codex | gemini | antigravity
#   native-event  : the agent's own event name (SessionStart, PreToolUse, …)
#
# Never fail the calling hook: always exit 0, tolerate missing deps.

TOOL="${1:-unknown}"
EVENT="${2:-unknown}"
HERE="$(cd "$(dirname "$0")" && pwd)"

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/quickshell-agents"
RAW_LOG="$STATE_DIR/raw.jsonl"
mkdir -p "$STATE_DIR" 2>/dev/null

have() { command -v "$1" >/dev/null 2>&1; }

# --- read the hook payload (JSON on stdin) ---------------------------------
payload="$(cat 2>/dev/null)"

now="$(date +%s)"
iso="$(date -Is 2>/dev/null)"

# If jq is missing we can still dump a minimal record and bail gracefully.
if ! have jq; then
  printf '{"ts":%s,"tool":"%s","event":"%s","raw_text":%q}\n' \
    "$now" "$TOOL" "$EVENT" "$payload" >>"$RAW_LOG" 2>/dev/null
  exit 0
fi

# raw payload as JSON if parseable, else keep the text
if printf '%s' "$payload" | jq -e . >/dev/null 2>&1; then
  raw_json="$payload"; raw_text=""
else
  raw_json="null"; raw_text="$payload"
fi

# --- process ancestry (pid + comm up to init) ------------------------------
# Agent hooks run as descendants of the agent CLI, which runs inside a
# terminal window; this chain lets us (and Layer 2) find both.
proc_chain() {
  local pid="$PPID" guard=0 stat comm ppid
  local acc=""
  while [ -n "$pid" ] && [ "$pid" -gt 1 ] && [ "$guard" -lt 40 ]; do
    stat="$(cat "/proc/$pid/stat" 2>/dev/null)" || break
    comm="$(printf '%s' "$stat" | sed -e 's/^[0-9]* (//' -e 's/).*//')"
    ppid="$(printf '%s' "$stat" | sed -e 's/.*) //' | awk '{print $2}')"
    acc="$acc$(jq -n --argjson pid "$pid" --arg comm "$comm" \
      --argjson ppid "${ppid:-0}" '{pid:$pid,comm:$comm,ppid:$ppid}')"
    pid="$ppid"; guard=$((guard + 1))
  done
  printf '%s' "$acc" | jq -sc '.'
}

# --- Hyprland window hosting this agent + its workspace --------------------
window_json() {
  have hyprctl || { printf 'null'; return; }
  local clients pid guard=0 match
  clients="$(hyprctl clients -j 2>/dev/null)" || { printf 'null'; return; }
  [ -z "$clients" ] && { printf 'null'; return; }
  pid="$PPID"
  while [ -n "$pid" ] && [ "$pid" -gt 1 ] && [ "$guard" -lt 50 ]; do
    match="$(printf '%s' "$clients" | jq -c --argjson p "$pid" \
      'map(select(.pid==$p)) | .[0] // empty' 2>/dev/null)"
    if [ -n "$match" ]; then printf '%s' "$match"; return; fi
    pid="$(sed -e 's/.*) //' "/proc/$pid/stat" 2>/dev/null | awk '{print $2}')"
    guard=$((guard + 1))
  done
  printf 'null'
}

chain="$(proc_chain)"
window="$(window_json)"
tty_val="$(tty 2>/dev/null || true)"

# agent-relevant environment (helps us learn what each CLI exposes)
env_json="$(jq -n 'env | to_entries
  | map(select(.key | test("^(CLAUDE|CODEX|GEMINI|ANTIGRAVITY|AGENT|ANTHROPIC|OPENAI|GOOGLE|TERM|TTY|SSH_|WAYLAND|HYPRLAND|XDG_SESSION)"; "i")))
  | from_entries' 2>/dev/null || printf 'null')"

# --- assemble the enriched blob -------------------------------------------
enriched="$(jq -nc \
  --argjson ts "$now" --arg iso "$iso" \
  --arg tool "$TOOL" --arg event "$EVENT" \
  --arg cwd "$PWD" --argjson pid "$$" --argjson ppid "$PPID" \
  --arg tty "$tty_val" --arg raw_text "$raw_text" \
  --argjson raw "$raw_json" --argjson chain "$chain" \
  --argjson window "$window" --argjson env "$env_json" \
  '{ts:$ts, iso:$iso, tool:$tool, event:$event,
    hook_pid:$pid, hook_ppid:$ppid, hook_cwd:$cwd, tty:$tty,
    raw:$raw, raw_text:$raw_text,
    proc_chain:$chain, window:$window, env:$env}' 2>/dev/null)"

[ -z "$enriched" ] && enriched="$(jq -nc --arg t "$TOOL" --arg e "$EVENT" --argjson ts "$now" '{ts:$ts,tool:$t,event:$e}')"

# Layer 1 sink: append the full raw record.
printf '%s\n' "$enriched" >>"$RAW_LOG" 2>/dev/null

# Hand off to Layer 2.
if [ -x "$HERE/normalize.sh" ]; then
  printf '%s' "$enriched" | "$HERE/normalize.sh" 2>/dev/null
fi

exit 0
