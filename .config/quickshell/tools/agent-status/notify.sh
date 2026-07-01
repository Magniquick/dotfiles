#!/usr/bin/env bash
# Clickable agent notification. Shows a desktop notification with a "Jump to
# agent" action; clicking it runs focus.sh for that session.
#
# Invoked DETACHED by normalize.sh (it blocks until click/timeout), so it must
# never run in the hook's foreground.
#
# Usage: notify.sh <session-id> <app> <title> <body>
#   app    → notify-send app-name (what a shell matcher keys on, e.g. "Antigravity")
#   title  → clean title (no emoji), body → the reason/detail

id="${1:-}"
app="${2:-AgentStatus}"
title="${3:-$app}"
body="${4:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"

# trace every fire (helps verify the transition gate; harmless)
printf '%s\t%s\t%s\n' "$(date +%s)" "$id" "$title" \
  >>"${XDG_RUNTIME_DIR:-/tmp}/quickshell-agents/notify.log" 2>/dev/null

command -v notify-send >/dev/null 2>&1 || exit 0

# -A KEY=LABEL renders an action button; notify-send prints KEY on click.
action="$(notify-send -a "$app" -t 8000 \
  -h "boolean:suppress-sound:true" \
  -h "string:x-canonical-private-synchronous:agent-$id" \
  -A "focus=Jump to agent" \
  "$title" "$body" 2>/dev/null)"

if [ "$action" = "focus" ]; then
  exec "$HERE/focus.sh" "$id"
fi
