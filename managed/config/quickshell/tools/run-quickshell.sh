#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

QSGO_QML_DIR="$ROOT_DIR/common/modules/qs-go/build/qml"
QSCAPTURE_QML_DIR="$ROOT_DIR/common/modules/qs-capture/build/qml"
UNIFIEDLYRICS_QML_DIR="$ROOT_DIR/common/modules/unified-lyrics-api/build/qml"

for d in "$QSGO_QML_DIR" "$QSCAPTURE_QML_DIR" "$UNIFIEDLYRICS_QML_DIR"; do
  if [[ ! -d "$d" ]]; then
    echo "QML module dir not found: $d" >&2
    echo "Build native modules first." >&2
    exit 1
  fi
done

# Qt typically uses QML2_IMPORT_PATH; some setups also read QML_IMPORT_PATH.
export QML2_IMPORT_PATH="$QSGO_QML_DIR:$QSCAPTURE_QML_DIR:$UNIFIEDLYRICS_QML_DIR${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
export QML_IMPORT_PATH="$QSGO_QML_DIR:$QSCAPTURE_QML_DIR:$UNIFIEDLYRICS_QML_DIR${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
# Standalone configs (e.g. powermenu) may use QtQuick.Controls through local
# MaterialKit components; ensure a valid controls style is always resolvable.
export QT_QUICK_CONTROLS_STYLE="${QT_QUICK_CONTROLS_STYLE:-Basic}"

if [[ "${1:-}" == "--standalone" ]]; then
  if [[ -z "${2:-}" ]]; then
    echo "Usage: qs --standalone <shell-dir> [quickshell args...]" >&2
    exit 2
  fi

  SHELL_DIR="$2"
  shift 2

  if [[ "$SHELL_DIR" != /* ]]; then
    SHELL_DIR="$ROOT_DIR/$SHELL_DIR"
  fi

  if [[ -d "$SHELL_DIR" && -f "$SHELL_DIR/shell.qml" ]]; then
    SHELL_DIR="$SHELL_DIR/shell.qml"
  fi

  exec quickshell --path "$SHELL_DIR" "$@"
fi

exec quickshell -p "$ROOT_DIR" "$@"
