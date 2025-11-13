#!/usr/bin/env bash
set +e # disable immediate exit on error

if [[ $SWAYNC_TOGGLE_STATE == true ]]; then {
	notify-send -a "swaync" "Bluetooth Enabled"
	rfkill unblock bluetooth
	bluetoothctl power on
} >/dev/null 2>&1 || :
else {
	notify-send -a "swaync" "Bluetooth Disabled"
	bluetoothctl power off; 
} >/dev/null 2>&1 || :
fi

exit 0