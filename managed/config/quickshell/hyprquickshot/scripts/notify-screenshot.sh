#!/bin/sh

summary=$1
body=$2
icon=$3
app="HyprShot"
ocr_action_timeout_ms=5000

path_to_uri() {
    target_path=$1
    if command -v realpath >/dev/null 2>&1; then
        resolved_path=$(realpath "$target_path" 2>/dev/null || printf '%s' "$target_path")
    else
        resolved_path=$target_path
    fi
    printf 'file://%s' "$resolved_path"
}

show_file() {
    target_path=$1
    [ -n "$target_path" ] || return 1
    [ -f "$target_path" ] || return 1

    target_uri=$(path_to_uri "$target_path")
    if command -v gdbus >/dev/null 2>&1; then
        gdbus call \
            --session \
            --dest org.freedesktop.FileManager1 \
            --object-path /org/freedesktop/FileManager1 \
            --method org.freedesktop.FileManager1.ShowItems \
            "[$target_uri]" \
            "" >/dev/null 2>&1 && return 0
    fi

    target_dir=$(dirname "$target_path")
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$target_dir" >/dev/null 2>&1 && return 0
    fi

    return 1
}

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

action=$(send_notification "$summary" "$body" "$icon" -t "$ocr_action_timeout_ms" --action=default=Show --action=ocr=OCR --wait 2>/dev/null || true)

if [ "$action" = "default" ]; then
    show_file "$icon"
    exit 0
fi

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
