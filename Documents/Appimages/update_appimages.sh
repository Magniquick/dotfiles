#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TWITCH_DIR="$ROOT_DIR/Twitch Drops Miner"
readonly LIBREPODS_DIR="$ROOT_DIR/LibrePods"

readonly TWITCH_TARGET="$TWITCH_DIR/Twitch.Drops.Miner-x86_64.AppImage"
readonly LIBREPODS_TARGET="$LIBREPODS_DIR/librepods-x86_64.AppImage"

readonly TWITCH_REPO="DevilXD/TwitchDropsMiner"
readonly TWITCH_ISSUE="234"
readonly TWITCH_ARTIFACT_NAME="Twitch.Drops.Miner.Linux.AppImage-x86_64"
readonly TWITCH_INNER_PATH="Twitch Drops Miner/Twitch.Drops.Miner-x86_64.AppImage"

readonly LIBREPODS_REPO="kavishdevar/librepods"
readonly LIBREPODS_WORKFLOW_FILE="ci-linux-rust.yml"
readonly LIBREPODS_ASSET_NAME="librepods-x86_64.AppImage"

DRY_RUN=0
FORCE=0
ONLY="all"

TWITCH_RESULT="skipped"
LIBREPODS_RESULT="skipped"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--dry-run] [--force] [--only twitch|librepods]

--dry-run         Show actions without replacing files.
--force           Ignore timestamp checks.
--only <target>   Update only one target: twitch or librepods.
USAGE
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

err() {
  printf 'ERROR: %s\n' "$*" >&2
}

check_gh_auth() {
  local target="$1"
  local auth_output

  if auth_output="$(gh auth status 2>&1)"; then
    return 0
  fi

  err "[$target] gh auth status failed:"
  while IFS= read -r line; do
    err "[$target]   $line"
  done <<<"$auth_output"
  err "[$target] Run: gh auth login"
  return 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Missing required command: $1"
    exit 1
  }
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      --force)
        FORCE=1
        ;;
      --only)
        shift
        [[ $# -gt 0 ]] || {
          err "--only requires a value"
          exit 1
        }
        case "$1" in
          twitch|librepods)
            ONLY="$1"
            ;;
          *)
            err "Invalid --only value: $1"
            exit 1
            ;;
        esac
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        err "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done
}

safe_cleanup_dir() {
  local d="$1"
  [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
}

update_twitch() {
  log "[twitch] Starting update check"
  [[ -f "$TWITCH_TARGET" ]] || {
    err "[twitch] Missing local AppImage: $TWITCH_TARGET"
    TWITCH_RESULT="failed"
    return 0
  }

  check_gh_auth "twitch" || {
    TWITCH_RESULT="failed"
    return 0
  }

  local issue_state
  issue_state="$(gh api "/repos/$TWITCH_REPO/issues/$TWITCH_ISSUE" 2>/dev/null | jq -r '.state')"
  if [[ -z "$issue_state" || "$issue_state" == "null" ]]; then
    err "[twitch] Could not read issue #$TWITCH_ISSUE state"
    TWITCH_RESULT="failed"
    return 0
  fi

  if [[ "$issue_state" != "open" ]]; then
    err "[twitch] Issue #$TWITCH_ISSUE is '$issue_state'; failing fast"
    TWITCH_RESULT="failed"
    return 0
  fi

  local runs_json run_id run_updated_at remote_epoch local_epoch
  runs_json="$(gh api "/repos/$TWITCH_REPO/actions/runs?branch=master&status=success&per_page=1")"
  run_id="$(jq -r '.workflow_runs[0].id // empty' <<<"$runs_json")"
  run_updated_at="$(jq -r '.workflow_runs[0].updated_at // empty' <<<"$runs_json")"

  if [[ -z "$run_id" || -z "$run_updated_at" ]]; then
    err "[twitch] No successful master run metadata found"
    TWITCH_RESULT="failed"
    return 0
  fi

  remote_epoch="$(date -u -d "$run_updated_at" +%s 2>/dev/null || true)"
  local_epoch="$(stat -c %Y "$TWITCH_TARGET")"

  [[ -n "$remote_epoch" ]] || {
    err "[twitch] Failed to parse run timestamp: $run_updated_at"
    TWITCH_RESULT="failed"
    return 0
  }

  log "[twitch] Local mtime: $(date -d "@$local_epoch" '+%Y-%m-%d %H:%M:%S %z')"
  log "[twitch] Latest successful master run: $(date -d "@$remote_epoch" '+%Y-%m-%d %H:%M:%S %z') (run_id=$run_id)"

  if (( FORCE == 0 )) && (( remote_epoch <= local_epoch )); then
    log "[twitch] Already latest"
    TWITCH_RESULT="already-latest"
    return 0
  fi

  local artifacts_json artifact_id artifact_expired
  artifacts_json="$(gh api "/repos/$TWITCH_REPO/actions/runs/$run_id/artifacts")"
  artifact_id="$(jq -r --arg name "$TWITCH_ARTIFACT_NAME" '.artifacts[] | select(.name == $name) | .id' <<<"$artifacts_json" | head -n1)"
  artifact_expired="$(jq -r --arg name "$TWITCH_ARTIFACT_NAME" '.artifacts[] | select(.name == $name) | .expired' <<<"$artifacts_json" | head -n1)"

  if [[ -z "$artifact_id" ]]; then
    err "[twitch] Artifact '$TWITCH_ARTIFACT_NAME' not found for run $run_id"
    TWITCH_RESULT="failed"
    return 0
  fi

  if [[ "$artifact_expired" == "true" ]]; then
    err "[twitch] Artifact '$TWITCH_ARTIFACT_NAME' is expired"
    TWITCH_RESULT="failed"
    return 0
  fi

  if (( DRY_RUN == 1 )); then
    log "[twitch] Dry run: would download artifact id $artifact_id and replace target"
    TWITCH_RESULT="updated"
    return 0
  fi

  local work_dir outer_zip outer_dir inner_dir inner_zip candidate tmp_target
  work_dir="$(mktemp -d)"
  outer_zip="$work_dir/artifact_outer.zip"
  outer_dir="$work_dir/outer"
  inner_dir="$work_dir/inner"
  mkdir -p "$outer_dir" "$inner_dir"

  if ! gh api "/repos/$TWITCH_REPO/actions/artifacts/$artifact_id/zip" > "$outer_zip"; then
    err "[twitch] Failed to download artifact zip"
    safe_cleanup_dir "$work_dir"
    TWITCH_RESULT="failed"
    return 0
  fi

  if ! unzip -q "$outer_zip" -d "$outer_dir"; then
    err "[twitch] Failed to extract outer zip"
    safe_cleanup_dir "$work_dir"
    TWITCH_RESULT="failed"
    return 0
  fi

  inner_zip="$outer_dir/${TWITCH_ARTIFACT_NAME}.zip"
  if [[ ! -f "$inner_zip" ]]; then
    inner_zip="$(find "$outer_dir" -maxdepth 2 -type f -name '*.zip' | head -n1 || true)"
  fi

  if [[ -z "$inner_zip" || ! -f "$inner_zip" ]]; then
    err "[twitch] Failed to find inner zip"
    safe_cleanup_dir "$work_dir"
    TWITCH_RESULT="failed"
    return 0
  fi

  if ! unzip -q "$inner_zip" -d "$inner_dir"; then
    err "[twitch] Failed to extract inner zip"
    safe_cleanup_dir "$work_dir"
    TWITCH_RESULT="failed"
    return 0
  fi

  candidate="$inner_dir/$TWITCH_INNER_PATH"
  if [[ ! -s "$candidate" ]]; then
    err "[twitch] AppImage not found after extraction: $TWITCH_INNER_PATH"
    safe_cleanup_dir "$work_dir"
    TWITCH_RESULT="failed"
    return 0
  fi

  tmp_target="$(mktemp "$TWITCH_DIR/.Twitch.Drops.Miner-x86_64.AppImage.new.XXXXXX")"
  install -m 0755 "$candidate" "$tmp_target"
  mv -f "$tmp_target" "$TWITCH_TARGET"

  safe_cleanup_dir "$work_dir"
  log "[twitch] Updated successfully"
  TWITCH_RESULT="updated"
}

update_librepods() {
  log "[librepods] Starting update check"
  [[ -f "$LIBREPODS_TARGET" ]] || {
    err "[librepods] Missing local AppImage: $LIBREPODS_TARGET"
    LIBREPODS_RESULT="failed"
    return 0
  }

  check_gh_auth "librepods" || {
    LIBREPODS_RESULT="failed"
    return 0
  }

  local runs_json run_id run_updated_at
  runs_json="$(gh api "/repos/$LIBREPODS_REPO/actions/workflows/$LIBREPODS_WORKFLOW_FILE/runs?status=success&per_page=1")"
  run_id="$(jq -r '.workflow_runs[0].id // empty' <<<"$runs_json")"
  run_updated_at="$(jq -r '.workflow_runs[0].updated_at // empty' <<<"$runs_json")"

  if [[ -z "$run_id" || -z "$run_updated_at" ]]; then
    err "[librepods] No successful workflow run metadata found for $LIBREPODS_WORKFLOW_FILE"
    LIBREPODS_RESULT="failed"
    return 0
  fi

  local remote_epoch local_epoch
  remote_epoch="$(date -u -d "$run_updated_at" +%s 2>/dev/null || true)"
  local_epoch="$(stat -c %Y "$LIBREPODS_TARGET")"

  [[ -n "$remote_epoch" ]] || {
    err "[librepods] Failed to parse run timestamp: $run_updated_at"
    LIBREPODS_RESULT="failed"
    return 0
  }

  log "[librepods] Local mtime: $(date -d "@$local_epoch" '+%Y-%m-%d %H:%M:%S %z')"
  log "[librepods] Latest successful workflow run: $(date -d "@$remote_epoch" '+%Y-%m-%d %H:%M:%S %z') (run_id=$run_id)"

  if (( FORCE == 0 )) && (( remote_epoch <= local_epoch )); then
    log "[librepods] Already latest"
    LIBREPODS_RESULT="already-latest"
    return 0
  fi

  if (( DRY_RUN == 1 )); then
    log "[librepods] Dry run: would download artifact from run $run_id and replace target"
    LIBREPODS_RESULT="updated"
    return 0
  fi

  local artifacts_json artifact_id artifact_expired
  artifacts_json="$(gh api "/repos/$LIBREPODS_REPO/actions/runs/$run_id/artifacts")"
  artifact_id="$(jq -r --arg name "$LIBREPODS_ASSET_NAME" '.artifacts[] | select(.name == $name) | .id' <<<"$artifacts_json" | head -n1)"
  artifact_expired="$(jq -r --arg name "$LIBREPODS_ASSET_NAME" '.artifacts[] | select(.name == $name) | .expired' <<<"$artifacts_json" | head -n1)"

  if [[ -z "$artifact_id" ]]; then
    err "[librepods] Artifact '$LIBREPODS_ASSET_NAME' not found for run $run_id"
    LIBREPODS_RESULT="failed"
    return 0
  fi

  if [[ "$artifact_expired" == "true" ]]; then
    err "[librepods] Artifact '$LIBREPODS_ASSET_NAME' is expired"
    LIBREPODS_RESULT="failed"
    return 0
  fi

  local work_dir artifact_zip extracted_dir candidate tmp_target
  work_dir="$(mktemp -d)"
  artifact_zip="$work_dir/artifact.zip"
  extracted_dir="$work_dir/extracted"
  mkdir -p "$extracted_dir"

  if ! gh api "/repos/$LIBREPODS_REPO/actions/artifacts/$artifact_id/zip" > "$artifact_zip"; then
    err "[librepods] Failed to download artifact zip"
    safe_cleanup_dir "$work_dir"
    LIBREPODS_RESULT="failed"
    return 0
  fi

  if ! unzip -q "$artifact_zip" -d "$extracted_dir"; then
    err "[librepods] Failed to extract artifact zip"
    safe_cleanup_dir "$work_dir"
    LIBREPODS_RESULT="failed"
    return 0
  fi

  candidate="$extracted_dir/$LIBREPODS_ASSET_NAME"
  if [[ ! -s "$candidate" ]]; then
    candidate="$(find "$extracted_dir" -type f -name "$LIBREPODS_ASSET_NAME" | head -n1 || true)"
  fi

  if [[ -z "$candidate" || ! -s "$candidate" ]]; then
    err "[librepods] AppImage '$LIBREPODS_ASSET_NAME' not found after extraction"
    safe_cleanup_dir "$work_dir"
    LIBREPODS_RESULT="failed"
    return 0
  fi

  tmp_target="$(mktemp "$LIBREPODS_DIR/.librepods-x86_64.AppImage.new.XXXXXX")"
  install -m 0755 "$candidate" "$tmp_target"
  mv -f "$tmp_target" "$LIBREPODS_TARGET"
  safe_cleanup_dir "$work_dir"

  log "[librepods] Updated successfully"
  LIBREPODS_RESULT="updated"
}

main() {
  parse_args "$@"

  for c in gh jq curl unzip stat date mktemp install mv find; do
    require_cmd "$c"
  done

  case "$ONLY" in
    all)
      update_twitch
      update_librepods
      ;;
    twitch)
      update_twitch
      ;;
    librepods)
      update_librepods
      ;;
  esac

  log "Summary: twitch=$TWITCH_RESULT librepods=$LIBREPODS_RESULT"

  local failed=0
  if [[ "$ONLY" == "all" || "$ONLY" == "twitch" ]]; then
    [[ "$TWITCH_RESULT" == "failed" ]] && failed=1
  fi
  if [[ "$ONLY" == "all" || "$ONLY" == "librepods" ]]; then
    [[ "$LIBREPODS_RESULT" == "failed" ]] && failed=1
  fi

  exit "$failed"
}

main "$@"
