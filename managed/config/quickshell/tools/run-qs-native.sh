#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QML_DIR="$ROOT_DIR/common/modules/qs-native/build/qml"

if [[ ! -d "$QML_DIR" ]]; then
  echo "qs-native QML dir not found: $QML_DIR" >&2
  echo "Build first: cd common/modules/qs-native && cmake -S . -B build && cmake --build build" >&2
  exit 1
fi

CONFIG_PATH="${1:-$ROOT_DIR/tmp/cxx-qt-test}"

export QML2_IMPORT_PATH="$QML_DIR${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"

quickshell -c "$CONFIG_PATH"
