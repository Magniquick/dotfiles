#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

find "$ROOT_DIR" \
  -path '*/build' -prune -o \
  -path '*/build-clang-tidy' -prune -o \
  -path '*/target' -prune -o \
  -path '*/.venv' -prune -o \
  -path '*/.cache' -prune -o \
  -path '*/archived' -prune -o \
  -path '*/examples' -prune -o \
  -path '*/outlook' -prune -o \
  -path '*/data' -prune -o \
  -path '*/.crush' -prune -o \
  -path '*/.agents' -prune -o \
  -path '*/.claude' -prune -o \
  -path '*/.playwright-mcp' -prune -o \
  -name 'example*.qml' -prune -o \
  -name '*.qml' -type f -print | sort
