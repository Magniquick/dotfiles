#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT_DIR/.cache/cargo-target}"

manifests=(
  "$ROOT_DIR/common/modules/material-popups/material-popups-backend/Cargo.toml"
  "$ROOT_DIR/common/modules/qsmath/ratex-helper/Cargo.toml"
)

for manifest in "${manifests[@]}"; do
  [[ -f "$manifest" ]] || continue
  echo "rustfmt: ${manifest#$ROOT_DIR/}"
  cargo fmt --manifest-path "$manifest" --check

  echo "clippy: ${manifest#$ROOT_DIR/}"
  cargo clippy --manifest-path "$manifest" --all-targets -- -D warnings
done
