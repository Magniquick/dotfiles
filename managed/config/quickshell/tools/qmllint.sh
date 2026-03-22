#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

args=(/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml)
QMLLINT_OVERRIDE_DIR="${XDG_RUNTIME_DIR:-/tmp}/qmllint-quickshell-overrides"

add_import_dir() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    args+=(-I "$dir")
  fi
}

prepare_quickshell_qmllint_overrides() {
  local window_src="/usr/lib/qt6/qml/Quickshell/_Window"
  local shortcuts_src="/usr/lib/qt6/qml/Quickshell/Hyprland/_GlobalShortcuts"
  local window_dst="$QMLLINT_OVERRIDE_DIR/Quickshell/_Window"
  local shortcuts_dst="$QMLLINT_OVERRIDE_DIR/Quickshell/Hyprland/_GlobalShortcuts"

  mkdir -p "$window_dst" "$shortcuts_dst"

  cp "$window_src/qmldir" "$window_dst/qmldir"
  cp "$window_src/quickshell-window.qmltypes" "$window_dst/quickshell-window.qmltypes"
  sed -i 's/isCreatable: false/isCreatable: true/' "$window_dst/quickshell-window.qmltypes"

  cp "$shortcuts_src/qmldir" "$shortcuts_dst/qmldir"
  cp "$shortcuts_src/quickshell-hyprland-global-shortcuts.qmltypes" "$shortcuts_dst/quickshell-hyprland-global-shortcuts.qmltypes"
  sed -i 's/prototype: "PostReloadHook"/prototype: "QObject"/' "$shortcuts_dst/quickshell-hyprland-global-shortcuts.qmltypes"

  add_qmldir "$window_dst/qmldir"
  add_qmldir "$shortcuts_dst/qmldir"
}

add_qmldir() {
  local qmldir_path="$1"
  if [[ -f "$qmldir_path" ]]; then
    args+=(-i "$qmldir_path")
  fi
}

if [[ -f "$ROOT_DIR/.qmlls.ini" ]]; then
  build_dir="$(sed -n 's/^buildDir="\(.*\)"$/\1/p' "$ROOT_DIR/.qmlls.ini" | head -n1)"
  if [[ -n "${build_dir:-}" ]]; then
    add_import_dir "$build_dir"
  fi

  import_paths="$(sed -n 's/^importPaths="\(.*\)"$/\1/p' "$ROOT_DIR/.qmlls.ini" | head -n1)"
  if [[ -n "${import_paths:-}" ]]; then
    IFS=: read -r -a qmlls_imports <<< "$import_paths"
    for dir in "${qmlls_imports[@]}"; do
      add_import_dir "$dir"
    done
  fi
fi

add_import_dir "$ROOT_DIR/common/modules/qs-go/build/qml"
add_import_dir "$ROOT_DIR/common/modules/qs-go/qml"
add_import_dir "$ROOT_DIR/common/modules/qs-capture/build/qml"
add_import_dir "$ROOT_DIR/common/modules/qs-capture/qml"
add_import_dir "$ROOT_DIR/common/modules/unified-lyrics-api/build/qml"
add_import_dir "$ROOT_DIR/common/modules/unified-lyrics-api/qml"

add_qmldir "$ROOT_DIR/qmldir"
add_qmldir "$ROOT_DIR/common/qmldir"
add_qmldir "$ROOT_DIR/common/materialkit/qmldir"
add_qmldir "$ROOT_DIR/bar/qmldir"
add_qmldir "$ROOT_DIR/sysclock/qmldir"
prepare_quickshell_qmllint_overrides

extra_args=()
targets=()

while (( $# > 0 )); do
  case "$1" in
    --json|--resource|-I|-i|-W)
      if (( $# < 2 )); then
        printf 'tools/qmllint.sh: option %s requires a value\n' "$1" >&2
        exit 2
      fi
      extra_args+=("$1" "$2")
      shift 2
      ;;
    --json=*|--resource=*|-I=*|-i=*|-W=*)
      extra_args+=("$1")
      shift
      ;;
    --)
      shift
      while (( $# > 0 )); do
        targets+=("$1")
        shift
      done
      ;;
    -*)
      extra_args+=("$1")
      shift
      ;;
    *)
      targets+=("$1")
      shift
      ;;
  esac
done

args+=("${extra_args[@]}")

if (( ${#targets[@]} <= 1 )); then
  exec "${args[@]}" "${targets[@]}"
fi

status=0
for target in "${targets[@]}"; do
  if ! output="$("${args[@]}" "$target" 2>&1)"; then
    printf '%s\n' "$output"
    status=1
  elif [[ -n "$output" ]]; then
    printf '%s\n' "$output"
  fi
done

exit "$status"
