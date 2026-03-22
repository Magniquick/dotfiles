#!/bin/sh

summary=$1
body=$2
icon=$3
app="HyprShot"
ocr_action_timeout_ms=5000

send_notification() {
    notify_summary=$1
    notify_body=$2
    notify_icon=$3
    shift 3

    if [ -n "$notify_icon" ]; then
        notify-send -a "$app" -i "$notify_icon" "$@" "$notify_summary" "$notify_body"
    else
        notify-send -a "$app" "$@" "$notify_summary" "$notify_body"
    fi
}

action=$(send_notification "$summary" "$body" "$icon" -t "$ocr_action_timeout_ms" --action=ocr=OCR --wait 2>/dev/null || true)

if [ "$action" != "ocr" ]; then
    exit 0
fi

if [ -z "$icon" ] || [ ! -f "$icon" ]; then
    send_notification "OCR failed" "Screenshot file not found" ""
    exit 0
fi

if ! command -v wl-copy >/dev/null 2>&1; then
    send_notification "OCR unavailable" "Install wl-copy to copy text" ""
    exit 0
fi

text=""
zbar_text=""
tesseract_text=""
ocr_backend_available=false

if command -v tesseract >/dev/null 2>&1; then
    ocr_backend_available=true
    tesseract_text=$(tesseract -l eng --psm 6 "$icon" - 2>/dev/null)
fi

if command -v zbarimg >/dev/null 2>&1; then
    ocr_backend_available=true
    zbar_text=$(zbarimg --quiet --raw "$icon" 2>/dev/null)
fi

if [ -n "$zbar_text" ]; then
    text="$zbar_text"
else
    text="$tesseract_text"
fi

if [ -n "$text" ]; then
    printf "%s" "$text" | wl-copy
    send_notification "OCR copied" "Text copied to clipboard" ""
elif [ "$ocr_backend_available" = true ]; then
    send_notification "OCR failed" "No text detected" ""
else
    send_notification "OCR unavailable" "Install tesseract or zbarimg to enable OCR" ""
fi
