#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
QMLFORMAT="${QMLFORMAT:-/usr/lib/qt6/bin/qmlformat}"

if [[ ! -x "$QMLFORMAT" ]]; then
  QMLFORMAT="$(command -v qmlformat || true)"
fi

if [[ -z "$QMLFORMAT" ]]; then
  echo "qmlformat not found" >&2
  exit 1
fi

mode=check
if [[ "${1:-}" == "--write" ]]; then
  mode=write
  shift
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

if (( $# > 0 )); then
  printf '%s\n' "$@" > "$tmp"
else
  "$ROOT_DIR/tools/qml-files.sh" > "$tmp"
fi

if [[ ! -s "$tmp" ]]; then
  exit 0
fi

if [[ "$mode" == "write" ]]; then
  exec "$QMLFORMAT" -i -F "$tmp"
fi

status=0
while IFS= read -r file; do
  formatted="$(mktemp)"
  "$QMLFORMAT" "$file" > "$formatted"
  if ! cmp -s "$file" "$formatted"; then
    printf 'qmlformat: %s is not formatted\n' "${file#$ROOT_DIR/}" >&2
    status=1
  fi
  rm -f "$formatted"
done < "$tmp"

exit "$status"
