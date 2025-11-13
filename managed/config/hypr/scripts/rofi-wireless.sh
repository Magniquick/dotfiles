#!/usr/bin/env bash

STATE_FILE="/tmp/rofi_toggle_state"

killall rofi 2>/dev/null

if [ ! -f "$STATE_FILE" ]; then
    echo "wifi" > "$STATE_FILE"
    rofi -theme "$XDG_CONFIG_HOME/rofi/config/iwd.rasi" -show wifi -modi "wifi:iwdrofimenu"
else
    LAST=$(cat "$STATE_FILE")
    if [ "$LAST" = "wifi" ]; then
        echo "bluetooth" > "$STATE_FILE"
        "$XDG_CONFIG_HOME/rofi/bin/rofi-bluetooth"
    else
        echo "wifi" > "$STATE_FILE"
        rofi -theme "$XDG_CONFIG_HOME/rofi/config/iwd.rasi" -show wifi -modi "wifi:iwdrofimenu"
    fi
fi
