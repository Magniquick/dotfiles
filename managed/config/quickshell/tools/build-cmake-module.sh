#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <module-name>" >&2
  exit 2
fi

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
MODULE_NAME="$1"
MODULE_DIR="$ROOT_DIR/common/modules/$MODULE_NAME"
BUILD_DIR="$MODULE_DIR/build"

case "$MODULE_NAME" in
  qs-native|material-popups|qsmath|unified-lyrics-api)
    GROUPED_BUILD=1
    SOURCE_DIR="$ROOT_DIR/common/modules/cxxqt"
    REAL_BUILD_DIR="$SOURCE_DIR/build"
    MODULE_BUILD_DIR="$REAL_BUILD_DIR/$MODULE_NAME"
    case "$MODULE_NAME" in
      qs-native) BUILD_TARGET="qsnative_qmldir" ;;
      material-popups) BUILD_TARGET="materialpopups_qmldir" ;;
      qsmath) BUILD_TARGET="qsmath_qmldir" ;;
      unified-lyrics-api) BUILD_TARGET="unifiedlyrics_qmldir" ;;
    esac
    ;;
  *)
    GROUPED_BUILD=0
    SOURCE_DIR="$MODULE_DIR"
    REAL_BUILD_DIR="$BUILD_DIR"
    MODULE_BUILD_DIR="$BUILD_DIR"
    BUILD_TARGET=""
    ;;
esac

if [[ ! -d "$MODULE_DIR" ]]; then
  echo "$MODULE_NAME module not found: $MODULE_DIR" >&2
  exit 1
fi

if ! command -v ninja >/dev/null 2>&1; then
  echo "ninja not found in PATH; install ninja to build $MODULE_NAME" >&2
  exit 1
fi

if [[ -f "$REAL_BUILD_DIR/CMakeCache.txt" ]]; then
  EXISTING_GENERATOR="$(sed -n 's/^CMAKE_GENERATOR:INTERNAL=//p' "$REAL_BUILD_DIR/CMakeCache.txt" | head -n1)"
  if [[ "$EXISTING_GENERATOR" != "Ninja" ]]; then
    rm -f "$REAL_BUILD_DIR/CMakeCache.txt"
    rm -rf "$REAL_BUILD_DIR/CMakeFiles"
  fi
fi

cmake -S "$SOURCE_DIR" -B "$REAL_BUILD_DIR" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
if [[ -n "$BUILD_TARGET" ]]; then
  cmake --build "$REAL_BUILD_DIR" --target "$BUILD_TARGET"
else
  cmake --build "$REAL_BUILD_DIR"
fi

if [[ "$GROUPED_BUILD" -eq 1 && ! -L "$BUILD_DIR" ]]; then
  rm -rf "$BUILD_DIR"
  ln -s "$MODULE_BUILD_DIR" "$BUILD_DIR"
fi

echo "QML2_IMPORT_PATH=$BUILD_DIR/qml"
