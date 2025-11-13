#!/usr/bin/env bash
# Screenshot wrapper:
# • If hyprlock or rofi is running → use hyprshot
# • Otherwise → fall back to Rofi script

if pgrep -x '^(hyprlock|rofi)$' >/dev/null 2>&1; then
    grim - | wl-copy
else
    exec "$XDG_CONFIG_HOME/rofi/bin/screenshot"
fi