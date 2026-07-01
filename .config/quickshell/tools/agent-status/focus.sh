#!/usr/bin/env bash
# Jump to the terminal (and exact kitty tab) hosting an agent session,
# from anywhere — any workspace, any active window.
#
# Usage:
#   focus.sh                 # focus the most-recently-updated agent
#   focus.sh <session-id>    # focus a specific session (substring match ok)
#   focus.sh --list          # list known agents
#
# Steps:
#   1. hyprctl focuswindow  → switches to the agent's workspace + kitty window
#   2. kitty @ focus-window → focuses the specific tab inside kitty
#      (requires kitty remote control; see kitty.conf listen_on)

set -uo pipefail
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/quickshell-agents"

have() { command -v "$1" >/dev/null 2>&1; }

if [ "${1:-}" = "--list" ]; then
  for f in "$STATE_DIR"/*.json; do
    [ -f "$f" ] || continue
    jq -r '"\(.id[0:12])  \(.tool)  \(.state)  ws:\(.workspace)  \(.cwd)"' "$f"
  done
  exit 0
fi

sel="${1:-}"

pick_file() {
  # exact file
  if [ -n "$sel" ] && [ -f "$STATE_DIR/$sel.json" ]; then
    printf '%s' "$STATE_DIR/$sel.json"; return
  fi
  # substring match on id
  if [ -n "$sel" ]; then
    for f in "$STATE_DIR"/*.json; do
      [ -f "$f" ] || continue
      case "$(jq -r '.id' "$f" 2>/dev/null)" in
        *"$sel"*) printf '%s' "$f"; return ;;
      esac
    done
  fi
  # fallback: most recently modified state file
  ls -t "$STATE_DIR"/*.json 2>/dev/null | head -1
}

f="$(pick_file)"
[ -z "$f" ] && { echo "no agent state found in $STATE_DIR" >&2; exit 1; }

addr="$(jq -r '.window_address // empty' "$f")"
ws="$(jq -r '.workspace // empty' "$f")"
kpid="$(jq -r '.term_pid // empty' "$f")"
tabpid="$(jq -r '.tab_shell_pid // empty' "$f")"

# 1) Hyprland: focus the kitty OS-window (also pulls its workspace into view).
if [ -n "$addr" ] && have hyprctl; then
  hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1
elif [ -n "$ws" ] && have hyprctl; then
  hyprctl dispatch workspace "$ws" >/dev/null 2>&1
fi

# 2) kitty: focus the exact tab. Needs `listen_on unix:/tmp/kitty-{kitty_pid}`.
if [ -n "$tabpid" ] && [ -n "$kpid" ] && have kitty; then
  sock="/tmp/kitty-$kpid"
  if [ -S "$sock" ]; then
    kitty @ --to "unix:$sock" focus-window --match "pid:$tabpid" >/dev/null 2>&1 \
      || kitty @ --to "unix:$sock" focus-tab --match "pid:$tabpid" >/dev/null 2>&1
  else
    echo "note: kitty socket $sock missing — enable remote control (see kitty.conf) and restart kitty" >&2
  fi
fi
