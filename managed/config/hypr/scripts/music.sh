#!/usr/bin/env bash

trackid=$(playerctl metadata --format "{{playerName}}")

if [[ "$trackid" == *"spotify"* ]]; then
    printf "Spotify "
elif [[ "$trackid" == *"brave"* ]]; then
    printf "Brave "
else
    printf "Music "
fi

echo -e " "
