#!/usr/bin/env bash
set -e

THUMB=/tmp/hyde-mpris
artUrl=$(playerctl metadata --format '{{mpris:artUrl}}' 2>/dev/null) || :

# Handle local file paths and URLs
if [[ "$artUrl" == file://* ]]; then
	artPath="${artUrl#file://}"
elif [[ "$artUrl" == http* ]]; then
	hash=$(echo -n "$artUrl" | sha256sum | awk '{print $1}')
	artPath="/tmp/$hash"
	[[ ! -f "$artPath" ]] && curl -s -o "$artPath" "$artUrl"
elif [[ "$artUrl" == '' ]]; then
	exit 1
fi

W=$(magick identify -format "%w" "$artPath")
H=$(magick identify -format "%h" "$artPath")

# only crop if not already square
if ((W != H)); then
	# bash’s ternary in arithmetic expansion
	SIDE=$((W < H ? W : H))
	magick "$artPath" \
		-gravity center \
		-crop "${SIDE}x${SIDE}+0+0" \
		+repage \
		"$artPath"
fi

# Update symbolic link if the art has changed

hash=$(basename "$artPath")
currentHash=$(basename "$(realpath "${THUMB}")")

[[ "$hash" == "$currentHash" ]] && exit 0
echo "Updating lock screen art"
ln -sf "$artPath" "${THUMB}"
pkill -USR2 hyprlock || echo "Is hyprlock running ?"
