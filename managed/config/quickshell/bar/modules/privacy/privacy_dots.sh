#!/usr/bin/env bash
# dependencies: pipewire (pw-dump), v4l2loopback-dkms, jq, dbus-send (dbus)
set -euo pipefail

JQ_BIN="${JQ:-jq}"
PW_DUMP_CMD="${PW_DUMP:-pw-dump}"

# Check critical dependencies upfront
missing_deps=""
if ! command -v "$JQ_BIN" >/dev/null 2>&1; then
  missing_deps="jq"
fi
if ! command -v "$PW_DUMP_CMD" >/dev/null 2>&1; then
  if [[ -n "$missing_deps" ]]; then
    missing_deps="$missing_deps, pw-dump"
  else
    missing_deps="pw-dump"
  fi
fi

if [[ -n "$missing_deps" ]]; then
  # Return error JSON for missing critical deps (use printf to avoid jq dependency)
  printf '{"error":"Missing: %s","mic":0,"cam":0,"loc":0,"scr":0,"mic_app":"","cam_app":"","loc_app":"","scr_app":""}\n' "$missing_deps"
  exit 0
fi

mic=0
cam=0
loc=0
scr=0

mic_app=""
cam_app=""
loc_app=""
scr_app=""

# mic & camera
if command -v "$PW_DUMP_CMD" >/dev/null 2>&1 && command -v "$JQ_BIN" >/dev/null 2>&1; then
  dump="$($PW_DUMP_CMD 2>/dev/null || true)"

  mic="$(
    printf '%s' "$dump" \
    | $JQ_BIN -r '
      [ .[]
        | select(.type=="PipeWire:Interface:Node")
        | select((.info.props."media.class"=="Audio/Source" or .info.props."media.class"=="Audio/Source/Virtual"))
        | select((.info.state=="running") or (.state=="running"))
      ] | (if length>0 then 1 else 0 end)
    ' 2>/dev/null || echo 0
  )"

  if [[ "$mic" -eq 1 ]]; then
    mic_app="$(
      printf '%s' "$dump" \
      | $JQ_BIN -r '
        [ .[]
          | select(.type=="PipeWire:Interface:Node")
          | select((.info.props."media.class"=="Stream/Input/Audio"))
          | select((.info.state=="running") or (.state=="running"))
          | .info.props["node.name"]
        ] | unique | join(", ")
      ' 2>/dev/null || echo ""
    )"
  fi

  if command -v fuser >/dev/null 2>&1; then
      cam=0
      for dev in /dev/video*; do
          if [ -e "$dev" ] && fuser "$dev" >/dev/null 2>&1; then
              cam=1
              break
          fi
      done
  else
      cam=0
  fi

  if command -v fuser >/dev/null 2>&1; then
      for dev in /dev/video*; do
          if [ -e "$dev" ] && fuser "$dev" >/dev/null 2>&1; then
              pids=$(fuser "$dev" 2>/dev/null)
              for pid in $pids; do
                  pname=$(ps -p "$pid" -o comm=)
                  if [[ -n "$pname" ]]; then
                      cam_app+="$pname, "
                  fi
              done
          fi
      done
      cam_app="${cam_app%, }"
  fi
fi

# location
if command -v gdbus >/dev/null 2>&1; then
  loc="$(
    if ps aux | grep [g]eoclue >/dev/null 2>&1; then
      echo 1
    else
      echo 0
    fi
  )"
fi

if command -v gdbus >/dev/null 2>&1; then
    if pids=$(pgrep -x geoclue); then
        loc=1
        for pid in $pids; do
            pname=$(ps -p "$pid" -o comm=)
            [[ -n "$pname" ]] && loc_app+="$pname, "
        done
        loc_app="${loc_app%, }"
    else
        loc=0
    fi
fi

# screen sharing
if command -v "$PW_DUMP_CMD" >/dev/null 2>&1 && command -v "$JQ_BIN" >/dev/null 2>&1; then
  if [[ -z "${dump:-}" ]]; then
    dump="$($PW_DUMP_CMD 2>/dev/null || true)"
  fi

  scr="$(
      printf '%s' "$dump" \
      | $JQ_BIN -e '
          [ .[]
            | select(.info?.props?)
            | select(
                (.info.props["media.name"]? // "")
                | test("^(xdph-streaming|gsr-default|game capture)")
            )
          ]
          | (if length > 0 then true else false end)
        ' >/dev/null && echo 1 || echo 0
    )"
fi

if [[ "$scr" -eq 1 ]]; then
    scr_app="$(
    printf '%s' "$dump" \
    |   $JQ_BIN -r '
        [ .[]
          | select(.type=="PipeWire:Interface:Node")
          | select((.info.props."media.class"=="Stream/Input/Video") or (.info.props."media.name"=="gsr-default_output") or (.info.props."media.name"=="game capture"))
          | select((.info.state=="running") or (.state=="running"))
          | .info.props["media.name"]
        ] | unique | join(", ")
      ' 2>/dev/null || echo ""
    )"
fi

# Generate output JSON with error handling
output=$($JQ_BIN -c -n \
  --argjson mic "$mic" \
  --argjson cam "$cam" \
  --argjson loc "$loc" \
  --argjson scr "$scr" \
  --arg mic_app "$mic_app" \
  --arg cam_app "$cam_app" \
  --arg loc_app "$loc_app" \
  --arg scr_app "$scr_app" \
  '{mic:$mic, cam:$cam, loc:$loc, scr:$scr, mic_app:$mic_app, cam_app:$cam_app, loc_app:$loc_app, scr_app:$scr_app}' 2>/dev/null) || {
  # Fallback error output if jq fails
  echo '{"error":"Failed to generate privacy status","mic":0,"cam":0,"loc":0,"scr":0,"mic_app":"","cam_app":"","loc_app":"","scr_app":""}'
  exit 0
}

# Validate that output is valid JSON
if ! printf '%s' "$output" | $JQ_BIN -e . >/dev/null 2>&1; then
  echo '{"error":"Invalid JSON output","mic":0,"cam":0,"loc":0,"scr":0,"mic_app":"","cam_app":"","loc_app":"","scr_app":""}'
  exit 0
fi

echo "$output"
