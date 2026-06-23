#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
CLANG_TIDY="${CLANG_TIDY:-clang-tidy}"
CLANG="${CLANG:-clang}"
CLANGXX="${CLANGXX:-clang++}"

modules=(
  material-popups
  qs-capture
  qs-native
  qsmath
  unified-lyrics-api
)

lint_build_target() {
  case "$1" in
    material-popups) echo materialpopups_plugin ;;
    qs-capture) echo qscapture_plugin ;;
    qs-native) echo qsnative_plugin ;;
    qsmath) echo qsmath_plugin ;;
    unified-lyrics-api) echo unifiedlyrics_plugin ;;
    *) return 1 ;;
  esac
}

fix=false
case "${1:-}" in
  --fix)
    fix=true
    shift
    ;;
  -h|--help)
    echo "usage: $0 [--fix]"
    exit 0
    ;;
esac

if (( $# > 0 )); then
  echo "usage: $0 [--fix]" >&2
  exit 2
fi

if ! command -v "$CLANG_TIDY" >/dev/null 2>&1; then
  echo "clang-tidy not found" >&2
  exit 1
fi

if ! command -v ninja >/dev/null 2>&1; then
  echo "ninja not found in PATH; install ninja to configure C++ lint builds" >&2
  exit 1
fi

if ! command -v "$CLANG" >/dev/null 2>&1 || ! command -v "$CLANGXX" >/dev/null 2>&1; then
  echo "clang and clang++ are required for clang-tidy compile databases" >&2
  exit 1
fi

configure_module() {
  local module="$1"
  local module_dir="$ROOT_DIR/common/modules/$module"
  local build_dir="$module_dir/build-clang-tidy"

  [[ -d "$module_dir" ]] || return 0

  cmake -S "$module_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_C_COMPILER="$CLANG" \
    -DCMAKE_CXX_COMPILER="$CLANGXX" \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

  cmake --build "$build_dir" --target $(lint_build_target "$module")
}

lint_module() {
  local module="$1"
  local module_dir="$ROOT_DIR/common/modules/$module"
  local build_dir="$module_dir/build-clang-tidy"
  local compile_db="$build_dir/compile_commands.json"
  local files=()

  [[ -d "$module_dir" ]] || return 0

  if [[ ! -f "$compile_db" ]]; then
    configure_module "$module"
  else
    cmake --build "$build_dir" --target $(lint_build_target "$module")
  fi

  if [[ ! -f "$compile_db" ]]; then
    echo "compile_commands.json missing for $module" >&2
    return 1
  fi

  mapfile -t files < <(
    find "$module_dir" \
      -path "$module_dir/build" -prune -o \
      -path "$module_dir/material-popups-backend/target" -prune -o \
      -path "$module_dir/ratex-helper/target" -prune -o \
      -path "$module_dir/vendor" -prune -o \
      -path "$module_dir/cpp/*.cpp" \
      -type f -print | sort
  )

  if (( ${#files[@]} == 0 )); then
    return 0
  fi

  echo "clang-tidy: common/modules/$module"
  line_filter="["
  for file in "${files[@]}"; do
    escaped="${file//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    line_filter+="{\"name\":\"$escaped\",\"lines\":[[1,2147483647]]},"
  done
  line_filter="${line_filter%,}]"

  tidy_args=(
    -p "$build_dir"
    "-header-filter=$module_dir/cpp/.*"
    "-line-filter=$line_filter"
  )
  if [[ "$fix" == true ]]; then
    tidy_args+=(-fix -fix-errors -format-style=file)
  fi
  "$CLANG_TIDY" "${tidy_args[@]}" "${files[@]}"
}

status=0
for module in "${modules[@]}"; do
  if ! lint_module "$module"; then
    status=1
  fi
done

exit "$status"
