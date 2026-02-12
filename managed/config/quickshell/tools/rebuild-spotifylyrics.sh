#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
MODULE_DIR="$ROOT_DIR/common/modules/spotify-lyrics-api"

echo "[rebuild-spotifylyrics] module: $MODULE_DIR"

# Go shared-library changes can be skipped by incremental CMake builds.
# Force a clean configure/build so libspotifylyrics_go.so is regenerated.
rm -rf "$MODULE_DIR/build"
cmake -S "$MODULE_DIR" -B "$MODULE_DIR/build"
cmake --build "$MODULE_DIR/build"

echo "[rebuild-spotifylyrics] restart quickshell ($ROOT_DIR)"
quickshell -p "$ROOT_DIR" kill || true

echo "[rebuild-spotifylyrics] done"
