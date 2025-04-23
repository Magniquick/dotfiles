#!/usr/bin/sh
hyprlock && systemctl --user start hyprunlock.service && systemctl --user disable --now hyprlock.service
