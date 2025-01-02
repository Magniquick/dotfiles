#!/bin/bash

THUMB=/tmp/hyde-mpris
artUrl=$(playerctl metadata --format '{{mpris:artUrl}}')

# Handle local file paths and URLs
if [[ "$artUrl" == file://* ]]; then
    artPath="${artUrl#file://}"
elif [[ "$artUrl" == http* ]]; then
    artPath="/tmp/$(echo -n "$artUrl" | sha256sum | awk '{print $1}').jpg"
    [[ ! -f "$artPath" ]] && curl -s -o "$artPath" "$artUrl"
elif [[ "$artUrl" == '' ]]; then
    echo "Invalid art URL: $artUrl" >&2
    exit 1
fi

magick "$artPath" -gravity center -crop \
	"$(magick identify -format '%[fx:min(w,h)]x%[fx:min(w,h)]' "$artPath")+0+0" +repage "$artPath"

# Update symbolic link if the art has changed
hash=$(echo -n "$artPath" | sha256sum | awk '{print $1}')
currentHash=$(basename "$(realpath "${THUMB}.jpg")" .jpg)
[[ "$hash" == "$currentHash" ]] && exit 0

ln -sf "$artPath" "${THUMB}.jpg"
pkill -USR2 hyprlock
