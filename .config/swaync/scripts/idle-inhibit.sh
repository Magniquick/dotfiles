#!/usr/bin/env bash
# ~/.config/swaync/scripts/idle-inhibit.sh

set -u  # fail on unset vars (we defensively guard env reads below)

LOCK_PID_FILE="/tmp/.idle_inhibit_pid"
WHO="IdleInhibit"
WHY="User requested inhibit"
WHAT="idle:sleep"
MODE="block"

status() {
  if [[ -f "$LOCK_PID_FILE" ]]; then
    local pid
    pid="$(<"$LOCK_PID_FILE")"
    if ps -p "$pid" > /dev/null 2>&1; then
      echo "Idle inhibit is ON (PID $pid)."
      return 0
    else
      # Stale file → clean up and report OFF
      rm -f "$LOCK_PID_FILE"
      echo "Idle inhibit is OFF (stale lock cleaned)."
      return 1
    fi
  else
    echo "Idle inhibit is OFF."
    return 1
  fi
}

turn_on() {
  status > /dev/null 2>&1 && { echo "Already ON"; return 0; }
  systemd-inhibit --what="$WHAT" --who="$WHO" --why="$WHY" --mode="$MODE" sleep infinity &
  local pid=$!
  echo "$pid" > "$LOCK_PID_FILE"
  echo "Idle inhibit ON (PID $pid)."
}

turn_off() {
  if [[ -f "$LOCK_PID_FILE" ]]; then
    local pid
    pid="$(<"$LOCK_PID_FILE")"
    if ps -p "$pid" > /dev/null 2>&1; then
      kill "$pid"
      echo "Killed inhibitor process $pid."
    else
      echo "Process $pid not running."
    fi
    rm -f "$LOCK_PID_FILE"
  else
    echo "No inhibitor process to kill."
  fi
  echo "Idle inhibit OFF."
}

case "${1:-}" in
  on)      turn_on ;;
  off)     turn_off ;;
  status)  status ;;
  is-on)   status >/dev/null 2>&1 && echo "true" || echo "false" ;;
  toggle)
    # Swaync sets SWAYNC_TOGGLE_STATE to "true" when the button should be ON.
    # Default to OFF if unset/empty.
    if [[ "${SWAYNC_TOGGLE_STATE:-false}" == "true" ]]; then
      turn_on > /dev/null 2>&1
    else
      turn_off > /dev/null 2>&1
    fi
    ;;
  *) echo "Usage: $0 {on|off|status|is-on|toggle}" ; exit 2 ;;
esac
