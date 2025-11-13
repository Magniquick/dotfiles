#!/usr/bin/env bash

player=$(playerctl metadata --format "{{mpris:trackid}}" 2>/dev/null)

switch_path(){
if [[ "$(basename "$(realpath "$XDG_CONFIG_HOME/hypr/hyprlock.conf")")" == "hyprlock.conf.$1" ]]; then
    echo "Switching hyprlock profile to $2"
	ln -sf "$XDG_CONFIG_HOME"/hypr/hyprlock/hyprlock.conf."$2" "$XDG_CONFIG_HOME"/hypr/hyprlock.conf
fi
}

echo "player: $player"
if [[ "$player" == "" ]]; then
    switch_path "music" "main"
else
    switch_path "main" "music"
fi