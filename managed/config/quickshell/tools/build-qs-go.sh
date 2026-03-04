#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE_DIR="$ROOT_DIR/common/modules/qs-go"
BUILD_DIR="$MODULE_DIR/build"

if [[ ! -d "$MODULE_DIR" ]]; then
  echo "qs-go module not found: $MODULE_DIR" >&2
  exit 1
fi

if ! command -v ninja >/dev/null 2>&1; then
  echo "ninja not found in PATH; install ninja to build qs-go" >&2
  exit 1
fi

if [[ -f "$BUILD_DIR/CMakeCache.txt" ]]; then
  EXISTING_GENERATOR="$(sed -n 's/^CMAKE_GENERATOR:INTERNAL=//p' "$BUILD_DIR/CMakeCache.txt" | head -n1)"
  if [[ "$EXISTING_GENERATOR" != "Ninja" ]]; then
    rm -f "$BUILD_DIR/CMakeCache.txt"
    rm -rf "$BUILD_DIR/CMakeFiles"
  fi
fi

cmake -S "$MODULE_DIR" -B "$BUILD_DIR" -G Ninja
cmake --build "$BUILD_DIR"

echo "QML2_IMPORT_PATH=$BUILD_DIR/qml"
