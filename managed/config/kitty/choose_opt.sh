#!/usr/bin/env bash
set -euo pipefail

target_window_id="${1:-}"

resolve_target_window_id() {
  if [[ -n "$target_window_id" ]]; then
    printf '%s\n' "$target_window_id"
    return 0
  fi

  kitten @ ls 2>/dev/null | jq -r --arg self "${KITTY_WINDOW_ID:-}" '
    def active_tab:
      if $self != "" then
        [.[].tabs[] | select(any(.windows[]; (.id | tostring) == $self))][0]
      else
        [.[].tabs[] | select(.is_active)][0]
      end;

    active_tab as $tab
    | if $tab == null then
        empty
      else
        (
          ($tab.active_window_history // [] | map(tostring) | map(select(. != $self)) | .[0])
          // ([$tab.windows[] | select((.id | tostring) != $self and (.is_active or .is_focused)) | .id | tostring][0])
          // ([$tab.windows[] | select((.id | tostring) != $self) | .id | tostring][0])
        )
      end
  '
}

clean_ansi() {
  perl -0777 -pe '
    my $ST  = qr/(?:\x07|\x1B\\|\x9C)/;
    my $osc = qr/(?s:\x1B\].*?$ST)/;
    my $csi = qr/[\x1B\x9B][][\\()#;?]*
                 (?:\d{1,4}(?:[;:]\d{0,4})*)?
                 [\dA-PR-TZcf-nq-uy=><~]/x;
    s/(?:$osc|$csi)//g;
  '
}

editor_choices() {
  for editor in micro nano code antigravity nvim; do
    if command -v "$editor" >/dev/null 2>&1; then
      case "$editor" in
        code) printf '%s\t%s\n' "vscode" "$editor" ;;
        *) printf '%s\t%s\n' "$editor" "$editor" ;;
      esac
    fi
  done
}

menu_height() {
  local count="$1"
  printf '%s\n' "$((count + 4))"
}

resize_picker_window() {
  local desired_lines="$1"
  local current_lines
  local increment

  for _ in 1 2 3 4; do
    current_lines="$(
      kitten @ ls 2>/dev/null |
        jq -r --arg self "${KITTY_WINDOW_ID:-}" '
          [.[].tabs[].windows[] | select((.id | tostring) == $self) | .lines][0] // empty
        '
    )"
    if [[ ! "$current_lines" =~ ^[0-9]+$ ]] || (( current_lines <= 0 )); then
      current_lines="$(tput lines 2>/dev/null || printf '0')"
    fi
    if [[ ! "$current_lines" =~ ^[0-9]+$ ]] || (( current_lines <= 0 )); then
      return 0
    fi

    increment="$((desired_lines - current_lines))"
    if (( increment == 0 )); then
      return 0
    fi
    kitten @ resize-window --self --axis=vertical --increment "$increment" >/dev/null 2>&1 || return 0
    sleep 0.03
  done
}

open_in_editor() {
  local source_file="$1"
  local editor
  local edit_file
  local editor_count

  editor_count="$(editor_choices | wc -l)"
  resize_picker_window "$(menu_height "$editor_count")"
  editor="$(
    editor_choices |
      fzf --height="$(menu_height "$editor_count")" --reverse --border --prompt="Editor > " --cycle --with-nth=1 --delimiter=$'\t' |
      cut -f2
  )"

  if [[ -z "$editor" ]]; then
    return 1
  fi

  edit_file="$(mktemp --suffix=.txt)"
  clean_ansi < "$source_file" > "$edit_file"
  rm -f "$source_file"

  case "$editor" in
    code|antigravity)
      "$editor" --wait "$edit_file"
      ;;
    *)
      "$editor" "$edit_file"
      ;;
  esac
  local status=$?

  rm -f "$edit_file"
  return "$status"
}

if [ -t 0 ]; then
  echo "No prior command output available." >&2
  sleep 1
  exit 1
fi

tmp="$(mktemp)"
cat > "$tmp"

actions=("Copy" "View in less" "Open in..." "Open in new window" "Search scrollback")
resize_picker_window "$(menu_height "${#actions[@]}")"
choice="$(
  printf '%s\n' "${actions[@]}" |
  fzf --height="$(menu_height "${#actions[@]}")" --reverse --border --prompt="Action > " --cycle
)"

case "${choice:-}" in
  "Copy")
    clean_ansi < "$tmp" | wl-copy
    rm -f "$tmp"
    echo "Copied."
    sleep 0.5
    ;;
  "View in less")
    less +G -fr "$tmp"
    rm -f "$tmp"
    ;;
  "Open in...")
    if ! editor_choices | grep -q .; then
      rm -f "$tmp"
      echo "No supported editors found." >&2
      sleep 1
      exit 1
    fi
    if ! open_in_editor "$tmp"; then
      rm -f "$tmp"
    fi
    ;;
  "Open in new window")
    kitty less +G -fr "$tmp"
    # kitty reads the file — clean up after a delay
    ( sleep 5; rm -f "$tmp" ) &
    ;;
  "Search scrollback")
    rm -f "$tmp"
    resolved_window_id="$(resolve_target_window_id)"
    if [[ -n "$resolved_window_id" ]]; then
      if ! error="$(kitten @ launch --match "window_id:${resolved_window_id}" --next-to "id:${resolved_window_id}" --location=hsplit --allow-remote-control kitty +kitten search.py "$resolved_window_id" 2>&1 >/dev/null)"; then
        printf 'Search scrollback failed:\n%s\n' "$error" >&2
        sleep 3
        exit 1
      fi
    else
      echo "No kitty window id available for search." >&2
      sleep 1
      exit 1
    fi
    ;;
  *)
    rm -f "$tmp"
    ;;
esac
