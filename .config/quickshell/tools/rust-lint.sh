#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
WORKSPACE_MANIFEST="$ROOT_DIR/common/modules/Cargo.toml"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT_DIR/common/modules/cxxqt/build/cargo/build}"

echo "rustfmt: common/modules/Cargo.toml"
cargo fmt --manifest-path "$WORKSPACE_MANIFEST" --all --check

echo "clippy: common/modules/Cargo.toml"
cargo clippy --manifest-path "$WORKSPACE_MANIFEST" --workspace --release --all-targets -- -D warnings
