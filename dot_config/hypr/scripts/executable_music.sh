#!/bin/env bash

trackid=$(playerctl metadata --format "{{mpris:trackid}}")

if [[ "$trackid" == *"spotify"* ]]; then
    echo -e "Spotify   "
elif [[ "$trackid" == *"brave"* ]]; then
    echo -e "Brave   "
else
    echo ""
fi
