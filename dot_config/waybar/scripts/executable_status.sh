#!/bin/bash
if [ ! -f /tmp/waybar-init ]; then
    stdbuf -i0 -o0 -e0 echo "{\"text\": \"  \", \"tooltip\": \"Initializing...\"}"
    touch /tmp/waybar-init
    exit 0
fi

updates=$(checkupdates | wc -l)
systemstatus=$(systemctl is-failed)
userstatus=$(systemctl --user is-failed)
google_tasks=$(~/Projects/google-to-do/.venv/bin/python ~/Projects/google-to-do/main.py)

if [[ -n "$google_tasks" ]]; then
    google_tasks="\rto-do: $google_tasks"
fi

if [[ "$systemstatus" == "running" && "$userstatus" == "running" ]]; then
    message="All systems operational."
else
    message="System status: $systemstatus\rUser status: $userstatus"
fi
if [[ $updates -eq 0 ]]; then
    updates=""
else
    updates="$updates updates available.\r"
fi
tooltip="$updates$message$google_tasks"

stdbuf -i0 -o0 -e0 echo "{\"text\": \"  \", \"tooltip\": \"$tooltip\"}"
