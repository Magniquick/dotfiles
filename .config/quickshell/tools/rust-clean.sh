#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

full=false
case "${1:-}" in
  --full)
    full=true
    shift
    ;;
  -h|--help)
    echo "usage: $0 [--full]"
    exit 0
    ;;
esac

if (( $# > 0 )); then
  echo "usage: $0 [--full]" >&2
  exit 2
fi

paths=(
  "$ROOT_DIR/.cache/cargo-target"
  "$ROOT_DIR/common/modules/cxxqt/build/cargo"
  "$ROOT_DIR/common/modules/qs-native/build/cargo"
  "$ROOT_DIR/common/modules/material-popups/build/cargo"
  "$ROOT_DIR/common/modules/qsmath/build/cargo"
)

if [[ "$full" == true ]]; then
  paths+=(
    "$ROOT_DIR/common/modules/cxxqt/build"
    "$ROOT_DIR/common/modules/qs-native/build"
    "$ROOT_DIR/common/modules/qs-native/build-clang-tidy"
    "$ROOT_DIR/common/modules/material-popups/build"
    "$ROOT_DIR/common/modules/material-popups/build-clang-tidy"
    "$ROOT_DIR/common/modules/material-popups/material-popups-backend/target"
    "$ROOT_DIR/common/modules/qsmath/build"
    "$ROOT_DIR/common/modules/qsmath/build-clang-tidy"
    "$ROOT_DIR/common/modules/qsmath/ratex-helper/target"
  )
fi

for path in "${paths[@]}"; do
  if [[ -e "$path" || -L "$path" ]]; then
    echo "removing ${path#$ROOT_DIR/}"
    rm -rf "$path"
  fi
done
