#!/usr/bin/env bash
set -euo pipefail

if [ ! -f /tmp/waybar-init ]; then
    stdbuf -i0 -o0 -e0 echo "{\"text\": \"  \", \"tooltip\": \"Initializing...\"}"
    touch /tmp/waybar-init
    exit 0
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
parent_dir="$(dirname -- "$script_dir")"

if google_tasks="$("$parent_dir/scripts/main.py")"; then
    :
else
    google_tasks='{"text": "", "tooltip": "Error fetching tasks"}'
fi

stdbuf -i0 -o0 -e0 echo "$google_tasks"
