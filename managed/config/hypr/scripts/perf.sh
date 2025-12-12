#!/usr/bin/env sh

HYPRGAMEMODE=$(hyprctl getoption animations:enabled | awk 'NR==1{print $2}')

killall -SIGUSR1 waybar # toggle waybar anways

if [ "$HYPRGAMEMODE" = 1 ] ; then
	hyprctl --batch "\
		keyword animations:enabled 0;\
		keyword animation borderangle,0; \
		keyword decoration:shadow:enabled 0;\
		keyword decoration:blur:enabled 0;\
		keyword decoration:fullscreen_opacity 1;\
		keyword decoration:inactive_opacity 0.97;\
		keyword general:gaps_in 0;\
		keyword general:gaps_out 0;\
		keyword general:border_size 0;\
		keyword decoration:rounding 0"
	notify-send -u low -a "Hyprland" "Hyprland" "Gamemode [ON]"
else
	notify-send -u low -a "Hyprland" "Hyprland" "Gamemode [OFF]"
	hyprctl reload
fi