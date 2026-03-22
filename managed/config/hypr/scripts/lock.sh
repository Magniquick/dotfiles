#!/usr/bin/env bash

set -eu

action="${1:-start}"

case "$action" in
    start)
        exec systemctl --user start hyprlock.service
        ;;
    stop)
        exec systemctl --user stop hyprlock.service
        ;;
    restart)
        exec systemctl --user try-restart hyprlock.service
        ;;
    *)
        printf 'Usage: %s [start|stop|restart]\n' "$0" >&2
        exit 1
        ;;
esac
