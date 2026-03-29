#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

echo "[launch-lockscreen.sh] Starting lockscreen..." | logger -t quickshell-lock
export QML2_IMPORT_PATH="$ROOT_DIR${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
export QML_IMPORT_PATH="$ROOT_DIR${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
export QT_QUICK_CONTROLS_STYLE="${QT_QUICK_CONTROLS_STYLE:-Basic}"

exec quickshell --no-duplicate --path "$ROOT_DIR/lockscreen"
