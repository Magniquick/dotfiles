#!/bin/bash
if [ ! -f /tmp/waybar-init ]; then
    stdbuf -i0 -o0 -e0 echo "{\"text\": \"  \", \"tooltip\": \"Initializing...\"}"
    touch /tmp/waybar-init
    exit 0
fi

updates=$(checkupdates | wc -l)
systemstatus=$(systemctl is-failed)
userstatus=$(systemctl --user is-failed)

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
tooltip="$updates$message"

stdbuf -i0 -o0 -e0 echo "{\"text\": \"  \", \"tooltip\": \"$tooltip\"}"
