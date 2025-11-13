#!/usr/bin/env bash
set +e # disable immediate exit on error

if [[ $SWAYNC_TOGGLE_STATE == true ]]; then {
    notify-send -a "swaync" "Wi-Fi Enabled"
	iwctl -- device wlan0 set-property Powered on
} > /dev/null 2>&1 || :
else {
    notify-send -a "swaync" "Wi-Fi Disabled"
	iwctl -- device wlan0 set-property Powered off
} > /dev/null 2>&1 || :
fi

exit 0