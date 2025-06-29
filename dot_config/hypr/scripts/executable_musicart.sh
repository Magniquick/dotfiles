#!/bin/env bash
set -e

THUMB=/tmp/hyde-mpris
artUrl=$(playerctl metadata --format '{{mpris:artUrl}}' 2>/dev/null) || :

hyprlock_relaunch() {
	systemctl  --user reload hyprlock.service
}

switch_path(){
if [[ "$(basename "$(realpath "$XDG_CONFIG_HOME/hypr/hyprlock.conf")")" == "hyprlock.conf.$1" ]]; then
	ln -sf "$XDG_CONFIG_HOME"/hypr/hyprlock.conf{".$2",}
	hyprlock_relaunch
fi
}

# Handle local file paths and URLs
if [[ "$artUrl" == file://* ]]; then
	artPath="${artUrl#file://}"
elif [[ "$artUrl" == http* ]]; then
	artPath="/tmp/$(echo -n "$artUrl" | sha256sum | awk '{print $1}').jpg"
	[[ ! -f "$artPath" ]] && curl -o "$artPath" "$artUrl"
elif [[ "$artUrl" == '' ]]; then
	#echo "No players found" >&2
	switch_path "music" "main"
	exit 1
fi

switch_path "main" "music"

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
hash=$(basename "$artPath" .jpg)
currentHash=$(basename "$(realpath "${THUMB}.jpg")" .jpg)

[[ "$hash" == "$currentHash" ]] && exit 0
ln -sf "$artPath" "${THUMB}.jpg"
pkill -USR2 hyprlock || echo "Is hyprlock running ?"
