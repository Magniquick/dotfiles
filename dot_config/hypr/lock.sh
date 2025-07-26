#!/usr/bin/sh
systemctl --user start hyprlock.service && systemctl --user start hyprunlock-mode.service && systemctl --user disable --now hyprlock-mode.service
