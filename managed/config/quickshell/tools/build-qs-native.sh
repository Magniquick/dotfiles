#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE_DIR="$ROOT_DIR/common/modules/qs-native"
BUILD_DIR="$MODULE_DIR/build"

if [[ ! -d "$MODULE_DIR" ]]; then
  echo "qs-native module not found: $MODULE_DIR" >&2
  exit 1
fi

cmake -S "$MODULE_DIR" -B "$BUILD_DIR"
cmake --build "$BUILD_DIR"

echo "QML2_IMPORT_PATH=$BUILD_DIR/qml"
