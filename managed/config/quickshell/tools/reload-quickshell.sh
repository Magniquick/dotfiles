#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

MODE="service"
WAIT_MS=2000
TAIL_LINES=120
SHOW_ALL=0

print_help() {
  cat <<'EOF'
Usage: ./tools/reload-quickshell.sh [options]

Options:
  --service      Restart quickshell.service (default; safest)
  --soft         Use Quickshell.reload(false)
  --hard         Use Quickshell.reload(true)
  --all          Print the full recent log tail instead of filtering to issues
  --tail N       Read the last N log lines (default: 120)
  --wait-ms N    Wait N milliseconds after reload (default: 2000)
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

if [[ "$MODE" == "service" ]]; then
  env -u XDG_RUNTIME_DIR systemctl --user restart quickshell
else
  quickshell ipc -n -p "$ROOT_DIR" call dev "$MODE"
fi
sleep "$(awk "BEGIN { printf \"%.3f\", $WAIT_MS / 1000 }")"

LOG_OUTPUT="$(quickshell log -n -p "$ROOT_DIR" --no-color --log-times -t "$TAIL_LINES")"

if [[ "$SHOW_ALL" -eq 1 ]]; then
  printf '%s\n' "$LOG_OUTPUT"
  exit 0
fi

ISSUES="$(printf '%s\n' "$LOG_OUTPUT" | grep -Ei '(^|[^[:alpha:]])(warn|warning|error|critical|fatal|failed)([^[:alpha:]]|$)' || true)"

if [[ -n "$ISSUES" ]]; then
  printf '%s\n' "$ISSUES"
else
  echo "No warnings or errors in the last $TAIL_LINES lines."
fi
