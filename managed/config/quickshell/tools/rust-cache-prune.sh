#!/usr/bin/env bash
set -euo pipefail

if ! command -v cargo-cache >/dev/null 2>&1; then
  cat >&2 <<'EOF'
cargo-cache not found.
Install it with: cargo install cargo-cache
Then rerun this script to prune Cargo registry/git/download caches.
EOF
  exit 1
fi

exec cargo cache --autoclean
