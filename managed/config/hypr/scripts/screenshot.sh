#!/usr/bin/env bash
# Screenshot wrapper:
# • If hyprlock or rofi is running → use hyprshot
# • Otherwise → fall back to quickshell

if pgrep -x '^(hyprlock|rofi)$' >/dev/null 2>&1; then
    grim - | wl-copy
else
	"$XDG_CONFIG_HOME/quickshell/qs" --standalone hyprquickshot
fi
