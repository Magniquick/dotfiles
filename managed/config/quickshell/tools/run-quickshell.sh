#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

QS_NATIVE_QML_DIR="$ROOT_DIR/common/modules/qs-native/build/qml"
SPOTIFYLYRICS_QML_DIR="$ROOT_DIR/common/modules/spotify-lyrics-api/build/qml"

for d in "$QS_NATIVE_QML_DIR" "$SPOTIFYLYRICS_QML_DIR"; do
  if [[ ! -d "$d" ]]; then
    echo "QML module dir not found: $d" >&2
    echo "Build native modules first." >&2
    exit 1
  fi
done

# Qt typically uses QML2_IMPORT_PATH; some setups also read QML_IMPORT_PATH.
export QML2_IMPORT_PATH="$QS_NATIVE_QML_DIR:$SPOTIFYLYRICS_QML_DIR${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
export QML_IMPORT_PATH="$QS_NATIVE_QML_DIR:$SPOTIFYLYRICS_QML_DIR${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"

exec quickshell -p "$ROOT_DIR" "$@"
