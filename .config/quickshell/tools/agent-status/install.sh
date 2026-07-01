#!/usr/bin/env bash
# Idempotent installer for the agent-status pipeline. Wires Claude, Codex, and
# Antigravity hooks to report.sh, enables the kitty tab-jump socket, and
# de-dupes Codex's own notifier. Safe to re-run; each step checks before writing.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPORT="$HERE/report.sh"
MARK="agent-status"   # marker string used to detect prior edits

say() { printf '  %s\n' "$*"; }

# ── Claude: ~/.claude/settings.json hooks (merged via jq) ──────────────────
claude() {
  local f="$HOME/.claude/settings.json"
  command -v jq >/dev/null || { say "claude: jq missing, skipped"; return; }
  [ -f "$f" ] || echo '{}' >"$f"
  local ev hooks='{}'
  for ev in SessionStart UserPromptSubmit PreToolUse PostToolUse Notification Stop SessionEnd; do
    hooks="$(jq --arg e "$ev" --arg c "$REPORT" \
      '. + {($e): [ {hooks: [ {type:"command", command:($c+" claude "+$e)} ]} ]}' <<<"$hooks")"
  done
  cp "$f" "$f.bak.$MARK" 2>/dev/null
  jq --argjson h "$hooks" '.hooks = $h' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
  say "claude: hooks written to $f"
}

# ── Codex: $CODEX_HOME/config.toml hooks + de-dup notify.sh ────────────────
codex() {
  local cfg="${CODEX_HOME:-$HOME/.codex}/config.toml"
  [ -f "$cfg" ] || { say "codex: $cfg not found, skipped"; return; }
  if grep -q "$MARK" "$cfg"; then
    say "codex: hooks already present"
  else
    cp "$cfg" "$cfg.bak.$MARK"
    { echo ""; echo "# --- $MARK: report Codex state to quickshell ---"
      local ev
      for ev in SessionStart UserPromptSubmit PreToolUse PostToolUse PermissionRequest Stop; do
        echo "[[hooks.$ev]]"
        echo "[[hooks.$ev.hooks]]"
        echo "type = \"command\""
        echo "command = '$REPORT codex $ev'"
      done
    } >>"$cfg"
    say "codex: hooks appended to $cfg (run /hooks in codex to trust)"
  fi
  # de-dup: silence Codex's own turn-complete notifier
  local nf="${CODEX_HOME:-$HOME/.codex}/notify.sh"
  if [ -f "$nf" ] && grep -qE '^[[:space:]]*notify-send' "$nf"; then
    sed -i 's/^\([[:space:]]*notify-send.*\)/# de-duped by '"$MARK"': \1/' "$nf"
    say "codex: notify.sh notify-send disabled (de-dup)"
  fi
}

# ── kitty: remote-control socket for tab-jump ─────────────────────────────
kitty_rc() {
  local f="$HOME/.config/kitty/kitty.conf"
  [ -f "$f" ] || { say "kitty: $f not found, skipped"; return; }
  if grep -q "listen_on unix:/tmp/kitty-{kitty_pid}" "$f"; then
    say "kitty: remote control already enabled"
  else
    { echo ""; echo "# --- $MARK: focus exact kitty tab of an agent (focus.sh) ---"
      echo "allow_remote_control socket-only"
      echo "listen_on unix:/tmp/kitty-{kitty_pid}"
    } >>"$f"
    say "kitty: remote control enabled (restart kitty to apply)"
  fi
}

# ── Antigravity: install the local hooks plugin ───────────────────────────
antigravity() {
  command -v antigravity >/dev/null || { say "antigravity: CLI not found, skipped"; return; }
  antigravity plugin install "$HERE/agy-plugin" >/dev/null 2>&1 \
    && say "antigravity: plugin installed" \
    || say "antigravity: plugin install failed"
}

echo "agent-status installer"
chmod +x "$HERE"/*.sh 2>/dev/null
claude
codex
kitty_rc
antigravity
echo "done. manual follow-ups: trust Codex hooks (/hooks), restart kitty for tab-jump."
