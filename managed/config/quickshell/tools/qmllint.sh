#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

declare -A import_dirs_seen=()
declare -A qmldirs_seen=()
args=(/usr/lib/qt6/bin/qmllint)

add_import_dir() {
  local dir="$1"
  if [[ -d "$dir" && -z "${import_dirs_seen[$dir]:-}" ]]; then
    import_dirs_seen["$dir"]=1
    args+=(-I "$dir")
  fi
}

add_qmldir() {
  local qmldir_path="$1"
  if [[ -f "$qmldir_path" && -z "${qmldirs_seen[$qmldir_path]:-}" ]]; then
    qmldirs_seen["$qmldir_path"]=1
    args+=(-i "$qmldir_path")
  fi
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

ini_value() {
  local ini_path="$1"
  local wanted_key="$2"
  local line key value

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="$(trim "$line")"
    case "$line" in
      ""|\#*|";"*|"["*) continue ;;
    esac
    [[ "$line" == *=* ]] || continue

    key="$(trim "${line%%=*}")"
    value="$(trim "${line#*=}")"
    if [[ "$key" == "$wanted_key" ]]; then
      if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
        value="${value:1:${#value}-2}"
      fi
      printf '%s\n' "$value"
      return 0
    fi
  done < "$ini_path"
}

add_qmlls_ini_paths() {
  local ini_path="$1"
  local build_dir import_paths dir

  [[ -f "$ini_path" ]] || return 0

  build_dir="$(ini_value "$ini_path" buildDir | head -n1)"
  if [[ -n "${build_dir:-}" ]]; then
    add_import_dir "$build_dir"
  fi

  import_paths="$(ini_value "$ini_path" importPaths | head -n1)"
  if [[ -n "${import_paths:-}" ]]; then
    IFS=: read -r -a qmlls_imports <<< "$import_paths"
    for dir in "${qmlls_imports[@]}"; do
      add_import_dir "$dir"
    done
  fi
}

add_import_dir /usr/lib/qt6/qml
add_qmlls_ini_paths "$ROOT_DIR/.qmlls.ini"

add_import_dir "$ROOT_DIR/common/modules/qs-native/build/qml"
add_import_dir "$ROOT_DIR/common/modules/qs-native/qml"
add_import_dir "$ROOT_DIR/common/modules/qs-capture/build/qml"
add_import_dir "$ROOT_DIR/common/modules/qs-capture/qml"
add_import_dir "$ROOT_DIR/common/modules/qsmath/build/qml"
add_import_dir "$ROOT_DIR/common/modules/qsmath/build-clang-tidy/qml"
add_import_dir "$ROOT_DIR/common/modules/qsmath/qml"
add_import_dir "$ROOT_DIR/common/modules/material-popups/build/qml"
add_import_dir "$ROOT_DIR/common/modules/material-popups/qml"
add_import_dir "$ROOT_DIR/common/modules/unified-lyrics-api/build/qml"
add_import_dir "$ROOT_DIR/common/modules/unified-lyrics-api/qml"

add_qmldir "$ROOT_DIR/qmldir"
add_qmldir "$ROOT_DIR/common/qmldir"
add_qmldir "$ROOT_DIR/common/materialkit/qmldir"
add_qmldir "$ROOT_DIR/bar/qmldir"
while IFS= read -r quickshell_qmldir; do
  add_qmldir "$quickshell_qmldir"
done < <(find /usr/lib/qt6/qml/Quickshell -name qmldir -print 2>/dev/null)
add_qmldir "$ROOT_DIR/common/modules/qsmath/qml/qsmath/qmldir"

extra_args=()
targets=()
print_args=false
json_passthrough=false
debug=false

while (( $# > 0 )); do
  case "$1" in
    --debug)
      debug=true
      shift
      ;;
    --print-args)
      print_args=true
      shift
      ;;
    --all)
      mapfile -t all_targets < <("$ROOT_DIR/tools/qml-files.sh")
      targets+=("${all_targets[@]}")
      shift
      ;;
    --json)
      if (( $# < 2 )); then
        printf 'tools/qmllint.sh: option %s requires a value\n' "$1" >&2
        exit 2
      fi
      json_passthrough=true
      extra_args+=("$1" "$2")
      shift 2
      ;;
    --json=*)
      json_passthrough=true
      extra_args+=("$1")
      shift
      ;;
    --resource|-I|-i|-W)
      if (( $# < 2 )); then
        printf 'tools/qmllint.sh: option %s requires a value\n' "$1" >&2
        exit 2
      fi
      extra_args+=("$1" "$2")
      shift 2
      ;;
    --resource=*|-I=*|-i=*|-W=*)
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

if [[ "$print_args" == true ]]; then
  printf '%q\n' "${args[@]}"
  exit 0
fi

if [[ "$json_passthrough" == true || ${#targets[@]} -eq 0 ]]; then
  exec "${args[@]}" "${targets[@]}"
fi

filter_qmllint_json() {
  jq '
    def no_type_for_property($properties):
      .message as $message
      | any($properties[]; $message == "No type found for property \"" + . + "\". This may be due to a missing import statement or incomplete qmltypes files.");
    def unresolved_property_type($type; $property):
      .message == "Type \"" + $type + "\" of property \"" + $property + "\" not found. This is likely due to a missing dependency entry or a type not being exposed declaratively.";
    def missing_member($members; $type):
      .message as $message
      | any($members[]; $message == "Member \"" + . + "\" not found on type \"" + $type + "\"");

    def ignored:
      # Quickshell 0.3.0 ships PanelWindow in its qmltypes as
      # isCreatable: false even though shell configs instantiate it at
      # runtime. Quickshell docs call PanelWindow resolution a known qmlls
      # limitation, so keep this as an exact-message metadata allowlist.
      .message == "Type PanelWindow is not creatable."
      # Quickshell exposes PopupWindow.anchor at runtime, but the generated
      # qmltypes leave PopupAnchor unresolved for qmllint. Ignore only the
      # current exact anchor-property messages.
      or no_type_for_property(["adjustment", "edges", "gravity"])
      or unresolved_property_type("PopupAnchor"; "anchor")
      # These Quickshell qmltypes refer to short or prototype type names that
      # qmllint cannot resolve even though the runtime and shipped modules work.
      or .message == "Property \"adapter\" has incomplete type \"FileViewAdapter\". You may be missing an import."
      or unresolved_property_type("BluetoothAdapter"; "defaultAdapter")
      or .message == "PostReloadHook was not found. Did you add all imports and dependencies?"
      or .message == "Type GlobalShortcut is used but it is not resolved"
      # Intentional dynamic QML access. ListView.itemAtIndex returns QQuickItem
      # statically, and Quickshell exposes QsWindow.window as QObject, so
      # qmllint cannot see these runtime properties.
      or missing_member(["kind", "_messageId", "tool"]; "QQuickItem")
      or missing_member(["visible"]; "QObject");

    .files |= map(
      # Drop only diagnostics covered by the allowlist above. Everything else
      # remains a normal qmllint finding and keeps failing the gate.
      .warnings = (.warnings // [] | map(select(ignored | not)))
      # qmllint marks the file unsuccessful before filtering. Recompute the
      # status so a file with only known metadata noise can pass.
      | .success = ((.warnings // []) | length == 0)
    )
  '
}

print_qmllint_json() {
  jq -r '
    .files[] as $file
    | $file.warnings[]?
    | "\(.type | ascii_upcase): \($file.filename):\(.line):\(.column): \(.message) [\(.id)]"
  '
}

run_qmllint_target() {
  local target="$1"
  local raw_json filtered_json raw_count suppressed_count remaining_count

  raw_json="$("${args[@]}" --json - "$target" 2>&1)"
  filtered_json="$(printf '%s\n' "$raw_json" | filter_qmllint_json)"
  raw_count="$(printf '%s\n' "$raw_json" | jq '[.files[].warnings[]?] | length')"
  remaining_count="$(printf '%s\n' "$filtered_json" | jq '[.files[].warnings[]?] | length')"
  suppressed_count="$((raw_count - remaining_count))"

  if [[ "$debug" == true && $suppressed_count -gt 0 ]]; then
    printf 'qmllint: suppressed %d known static-tooling diagnostic(s) for %s\n' \
      "$suppressed_count" "$target" >&2
  fi

  if (( remaining_count > 0 )); then
    printf '%s\n' "$filtered_json" | print_qmllint_json
    return 1
  fi
}

run_targets_parallel() {
  local jobs tmpdir running status i target output_file status_file

  jobs="${QMLLINT_JOBS:-$(nproc 2>/dev/null || printf '4')}"
  [[ "$jobs" =~ ^[0-9]+$ ]] || jobs=4
  (( jobs > 0 )) || jobs=1

  tmpdir="$(mktemp -d)"
  trap "rm -rf '$tmpdir'" EXIT

  running=0
  for i in "${!targets[@]}"; do
    target="${targets[$i]}"
    output_file="$tmpdir/$i.out"
    status_file="$tmpdir/$i.status"

    (
      set +e
      run_qmllint_target "$target" > "$output_file" 2>&1
      printf '%s\n' "$?" > "$status_file"
    ) &

    running=$((running + 1))
    if (( running >= jobs )); then
      wait -n || true
      running=$((running - 1))
    fi
  done

  while (( running > 0 )); do
    wait -n || true
    running=$((running - 1))
  done

  status=0
  for i in "${!targets[@]}"; do
    output_file="$tmpdir/$i.out"
    status_file="$tmpdir/$i.status"
    if [[ -s "$output_file" ]]; then
      cat "$output_file"
    fi
    if [[ ! -f "$status_file" || "$(cat "$status_file")" != 0 ]]; then
      status=1
    fi
  done

  return "$status"
}

run_targets_parallel
