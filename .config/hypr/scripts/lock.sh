#!/usr/bin/env bash

set -eu

qs ipc -p "$(realpath ~/.config/quickshell)" call lockscreen lock
