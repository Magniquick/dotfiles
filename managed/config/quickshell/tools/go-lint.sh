#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LINTERS="govet,staticcheck,revive,gosec,errcheck,ineffassign,unused,unconvert,misspell,prealloc,bodyclose,noctx"
MODULES=(
  "common/modules/qs-go"
  "common/modules/unified-lyrics-api"
)

if ! command -v golangci-lint >/dev/null 2>&1; then
  echo "go-lint: golangci-lint not found" >&2
  exit 1
fi

for module in "${MODULES[@]}"; do
  echo "go-lint: ${module}"
  (
    cd "${ROOT_DIR}/${module}"
    golangci-lint run ./... --enable="${LINTERS}"
  )
done
