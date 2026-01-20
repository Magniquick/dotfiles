#!/usr/bin/env sh
set -eu

# Point qmllint at system Qt/QML modules, including Quickshell.
exec /usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml "$@"
