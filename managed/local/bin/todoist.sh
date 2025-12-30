#!/usr/bin/env bash

# grab the address (will be empty if no matching window)
addr=$(hyprctl clients -j | jq -r 'limit(1; .[] 
	| select(.initialTitle | test("app.todoist.com_/app/today")) 
	| .address)')
if [[ -n "$addr" ]]; then
	# $addr is not empty -> we found a matching client
	hyprctl dispatch focuswindow address:"$addr"
else
	# $addr is empty -> no matching client
	exec brave --app="https://app.todoist.com/app/today"
fi
