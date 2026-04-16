#!/usr/bin/env bash
set -euo pipefail

clean_ansi() {
  perl -0777 -pe '
    my $ST  = qr/(?:\x07|\x1B\\|\x9C)/;
    my $osc = qr/(?s:\x1B\].*?$ST)/;
    my $csi = qr/[\x1B\x9B][][\\()#;?]*
                 (?:\d{1,4}(?:[;:]\d{0,4})*)?
                 [\dA-PR-TZcf-nq-uy=><~]/x;
    s/(?:$osc|$csi)//g;
  '
}

if [ -t 0 ]; then
  echo "No prior command output available." >&2
  sleep 1
  exit 1
fi

tmp="$(mktemp)"
cat > "$tmp"

choice="$(
  printf '%s\n' "Copy" "View in less" "Open in new window" |
  fzf --height=10 --reverse --border --prompt="Action > " --cycle
)"

case "${choice:-}" in
  "Copy")
    clean_ansi < "$tmp" | wl-copy
    rm -f "$tmp"
    echo "Copied."
    sleep 0.5
    ;;
  "View in less")
    less +G -fr "$tmp"
    rm -f "$tmp"
    ;;
  "Open in new window")
    kitty less +G -fr "$tmp"
    # kitty reads the file — clean up after a delay
    ( sleep 5; rm -f "$tmp" ) &
    ;;
  *)
    rm -f "$tmp"
    ;;
esac
