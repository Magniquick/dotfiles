#!/usr/bin/env bash

STATE_FILE="/tmp/rofi_toggle_state"

killall rofi 2>/dev/null

if [ ! -f "$STATE_FILE" ]; then
    echo "wifi" > "$STATE_FILE"
    vicinae vicinae://extensions/dagimg-dot/wifi-commander/scan-wifi
else
    LAST=$(cat "$STATE_FILE")
    if [ "$LAST" = "wifi" ]; then
        echo "bluetooth" > "$STATE_FILE"
        "$XDG_CONFIG_HOME/rofi/bin/rofi-bluetooth"
    else
        echo "wifi" > "$STATE_FILE"
        vicinae vicinae://extensions/dagimg-dot/wifi-commander/scan-wifi
    fi
fi
