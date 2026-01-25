#!/bin/sh

notify_and_handle_action() {
    summary=$1
    body=$2
    icon=$3
    app="HyprShot"

    if [ -n "$icon" ]; then
        action=$(notify-send -a "$app" "$summary" "$body" -i "$icon" --action=ocr=OCR --wait)
    else
        action=$(notify-send -a "$app" "$summary" "$body" --action=ocr=OCR --wait)
    fi

    if [ "$action" != "ocr" ]; then
        exit 0
    fi

    if [ -z "$icon" ] || [ ! -f "$icon" ]; then
        notify-send -a "$app" "OCR failed" "Screenshot file not found"
        exit 0
    fi
    if ! command -v tesseract >/dev/null 2>&1; then
        notify-send -a "$app" "OCR unavailable" "Install tesseract to enable OCR"
        exit 0
    fi
    if ! command -v wl-copy >/dev/null 2>&1; then
        notify-send -a "$app" "OCR unavailable" "Install wl-copy to copy text"
        exit 0
    fi

    text=$(tesseract "$icon" - 2>/dev/null)
    if [ -n "$text" ]; then
        printf "%s" "$text" | wl-copy
        notify-send -a "$app" "OCR copied" "Text copied to clipboard"
    else
        notify-send -a "$app" "OCR failed" "No text detected"
    fi
}

if [ "$1" = "--wait" ]; then
    shift
    notify_and_handle_action "$@"
    exit 0
fi

summary=$1
body=$2
icon=$3

if command -v setsid >/dev/null 2>&1; then
    setsid -f "$0" --wait "$summary" "$body" "$icon" >/dev/null 2>&1
else
    nohup "$0" --wait "$summary" "$body" "$icon" >/dev/null 2>&1 &
fi
