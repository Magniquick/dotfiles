#!/usr/bin/sh
hyprlock && systemctl --user start hyprunlock-mode.service && systemctl --user disable --now hyprlock-mode.service
