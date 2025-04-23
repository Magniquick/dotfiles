#!/bin/bash
#set -e

THUMB=/tmp/hyde-mpris
artUrl=$(playerctl metadata --format '{{mpris:artUrl}}') || :
# Handle local file paths and URLs
if [[ "$artUrl" == file://* ]]; then
    artPath="${artUrl#file://}"
elif [[ "$artUrl" == http* ]]; then
    artPath="/tmp/$(echo -n "$artUrl" | sha256sum | awk '{print $1}').jpg"
    [[ ! -f "$artPath" ]] && curl -s -o "$artPath" "$artUrl"
elif [[ "$artUrl" == '' ]]; then
    echo "No players found" >&2
    if [[ "$(basename "$(realpath "$XDG_CONFIG_HOME/hypr/hyprlock.conf")")" == "hyprlock.conf.music" ]]; then
        ln -sf "$XDG_CONFIG_HOME"/hypr/hyprlock.conf{.main,} 
        pgrep -x hyprlock && (pkill -USR1 hyprlock && hyprlock)
    fi
    exit 1
fi
if [[ "$(basename "$(realpath "$XDG_CONFIG_HOME/hypr/hyprlock.conf")")" == "hyprlock.conf.main" ]]; then
    ln -sf "$XDG_CONFIG_HOME"/hypr/hyprlock.conf{.music,}
    pgrep -x hyprlock && (pkill -USR1 hyprlock && hyprlock)
fi
magick "$artPath" -gravity center -crop \
    "$(magick identify -format '%[fx:min(w,h)]x%[fx:min(w,h)]' "$artPath")+0+0" +repage "$artPath"

# Update symbolic link if the art has changed
hash=$(echo -n "$artPath" | sha256sum | awk '{print $1}')
currentHash=$(basename "$(realpath "${THUMB}.jpg")" .jpg)
[[ "$hash" == "$currentHash" ]] && exit 0
ln -sf "$artPath" "${THUMB}.jpg"
pkill -USR2 hyprlock || echo "Is hyprlock running ?"

