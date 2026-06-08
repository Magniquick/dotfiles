#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

MODE="service"
WAIT_MS=5000
TAIL_LINES=120
SHOW_ALL=0
SERVICE_NAME="quickshell.service"

print_help() {
  cat <<'EOF'
Usage: ./tools/reload-quickshell.sh [options]

Options:
  --service      Restart quickshell.service (default; safest)
  --soft         Use Quickshell.reload(false)
  --hard         Use Quickshell.reload(true)
  --all          Print full logs instead of filtering to issues
  --tail N       Read the last N Quickshell log lines (default: 120)
  --wait-ms N    Wait N milliseconds after reload (default: 5000)
  --help         Show this help text
EOF
}

while (($# > 0)); do
  case "$1" in
    --service)
      MODE="service"
      shift
      ;;
    --soft)
      MODE="reload"
      shift
      ;;
    --hard)
      MODE="reloadHard"
      shift
      ;;
    --all)
      SHOW_ALL=1
      shift
      ;;
    --tail)
      TAIL_LINES="${2:?missing value for --tail}"
      shift 2
      ;;
    --wait-ms)
      WAIT_MS="${2:?missing value for --wait-ms}"
      shift 2
      ;;
    --help|-h)
      print_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      print_help >&2
      exit 2
      ;;
  esac
done

RESTART_STATUS=0

service_properties() {
  systemctl --user show "$SERVICE_NAME" \
    --property=ActiveState,SubState,InvocationID,Result,NRestarts,ExecMainCode,ExecMainStatus \
    --no-pager
}

service_property() {
  systemctl --user show "$SERVICE_NAME" --property="$1" --value --no-pager
}

last_start_journal() {
  journalctl --user -u "$SERVICE_NAME" -I --no-pager -o cat
}

last_start_journal_json() {
  journalctl --user -u "$SERVICE_NAME" -I --no-pager -o json
}

last_start_journal_issues() {
  last_start_journal_json | jq -r '
    def message:
      if (.MESSAGE | type) == "array" then
        .MESSAGE | implode
      else
        .MESSAGE // ""
      end;
    def plain:
      message
      | gsub("\u001b\\[[0-9;]*m"; "")
      | ltrimstr(" ");
    select(
      ((.PRIORITY | tonumber? // 999) <= 4)
      or (plain | startswith("WARN:"))
      or (plain | startswith("WARNING:"))
      or (plain | startswith("ERROR:"))
      or (plain | startswith("CRITICAL:"))
      or (plain | startswith("FATAL:"))
      or (plain | contains("Failed with result"))
      or (plain | contains("status=255/EXCEPTION"))
      or (plain | contains("start-limit-hit"))
    )
    | plain
  '
}

service_state_is_ok() {
  local active_state sub_state result exec_status
  active_state="$(service_property ActiveState)" || return 1
  sub_state="$(service_property SubState)" || return 1
  result="$(service_property Result)" || return 1
  exec_status="$(service_property ExecMainStatus)" || return 1

  [[ "$active_state" == "active" && "$sub_state" == "running" && "$result" == "success" && "$exec_status" == "0" ]]
}

sleep_seconds() {
  printf '%d.%03d' "$((WAIT_MS / 1000))" "$((WAIT_MS % 1000))"
}

print_service_diagnostics() {
  echo "quickshell.service is not healthy after reload." >&2
  echo >&2
  echo "quickshell.service state:" >&2
  service_properties >&2 || true
  echo >&2
  systemctl --user status "$SERVICE_NAME" --no-pager -l >&2 || true
  echo >&2
  echo "quickshell.service journal from last start:" >&2
  last_start_journal >&2 || true
}

if [[ "$MODE" == "service" ]]; then
  systemctl --user reset-failed "$SERVICE_NAME" || true
  timeout "$(sleep_seconds)" env -u XDG_RUNTIME_DIR systemctl --user --wait restart "$SERVICE_NAME" || RESTART_STATUS=$?
else
  quickshell ipc -n -p "$ROOT_DIR" call dev "$MODE"
  sleep "$(sleep_seconds)"
fi

if [[ "$RESTART_STATUS" -ne 0 && "$RESTART_STATUS" -ne 124 ]] || ! service_state_is_ok; then
  print_service_diagnostics
  exit 1
fi

JOURNAL_OUTPUT="$(last_start_journal || true)"
JOURNAL_ISSUES="$(last_start_journal_issues || true)"
if ! service_state_is_ok; then
  print_service_diagnostics
  exit 1
fi

if [[ "$SHOW_ALL" -eq 1 ]]; then
  echo "== quickshell log =="
  quickshell log -n -p "$ROOT_DIR" --no-color --log-times -t "$TAIL_LINES" || true
  echo "== quickshell.service journal from last start =="
  printf '%s\n' "$JOURNAL_OUTPUT"
  exit 0
fi

if [[ -n "$JOURNAL_ISSUES" ]]; then
  printf '%s\n' "$JOURNAL_ISSUES"
  exit 1
else
  echo "No warnings or errors in the latest $SERVICE_NAME start."
fi
