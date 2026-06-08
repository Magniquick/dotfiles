#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

find "$ROOT_DIR/common/modules" -mindepth 2 -maxdepth 2 -type d -name build-clang-tidy -print -exec rm -rf {} +
