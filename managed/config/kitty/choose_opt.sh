#!/usr/bin/env bash
set -euo pipefail

exists() {
  command -v "$1" >/dev/null 2>&1
}

exists fzf || { echo "fzf not found. Install it first."; exit 1; }

clip() {
	if exists wl-copy; then
		# check if wl-clip-persist is running to avoid losing clipboard on exit
		# if ! pgrep -x wl-clip-persist >/dev/null 2>&1; then
		# 	echo "Error: wl-clip-persist is not running. Start it to keep clipboard after exit." >&2
		# 	sleep 1
		# 	return 1
		# fi
	    wl-copy
	elif exists xclip; then
		xclip -selection clipboard -in
	elif exists xsel; then
		xsel -b
	elif exists termux-clipboard-set; then
		termux-clipboard-set
	elif [[ $OSTYPE == linux* && -r /proc/version && $(< /proc/version) =~ [Mm]icrosoft ]]; then
		clip.exe
	elif [[ $OSTYPE == darwin* ]]; then
		pbcopy
	elif [[ $OSTYPE == cygwin* || $OSTYPE == msys* ]]; then
		tee > /dev/clipboard
	else
		echo "No clipboard utility found." >&2
		return 1
	fi
}

# Strip ANSI/terminal control sequences (CSI, OSC, DCS, PM, APC).
# Prefer perl for robustness; fall back to a simpler sed if perl is missing.
clean_ansi() {
  if exists perl; then
    # Slurp whole input (-0777) so OSC ... ST can span lines.
	# see https://raw.githubusercontent.com/chalk/ansi-regex/refs/heads/main/index.js
    perl -0777 -pe '
      # ST: BEL | ESC \ | 0x9C
      my $ST  = qr/(?:\x07|\x1B\\|\x9C)/;

      # OSC: ESC ] ... ST   (non-greedy up to the first ST)
      my $osc = qr/(?s:\x1B\].*?$ST)/;

      # CSI and related: ESC/C1, optional intermediates, optional params, then final byte
      my $csi = qr/[\x1B\x9B][][\\()#;?]*
                   (?:\d{1,4}(?:[;:]\d{0,4})*)?
                   [\dA-PR-TZcf-nq-uy=><~]/x;

      s/(?:$osc|$csi)//g;
    '
  else
    # Fallback: strip most CSI sequences (won't catch OSC).
	echo "Warning: perl not found; using simpler ANSI stripper that may miss some sequences." >&2
    awk '{ gsub(/\033\[[0-9;:]*[ -/]*[@-~]/,""); print }'
  fi
}

# Slurp Kitty's @last_cmd_output once
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
if [ -t 0 ]; then
	# No data on stdin
	echo "No prior command output available." >&2
	sleep 1
	exit 1
else
	cat > "$tmp"
fi

options=("Copy last command output" "View last command in less" "View last command in a new kitty window")
choice="$(
	printf '%s\n' "${options[@]}" |
	fzf --height=10 --reverse --border --prompt="Action > " --cycle
)"

case "${choice:-}" in
	"Copy last command output")
	if clean_ansi < "$tmp" | clip; then
		echo "✅ Copied (ANSI stripped)."
		sleep 1
		exit 0
	else
		echo "❌ Could not copy: no clipboard utility available."
		exit 1
	fi
	;;
	"View last command in less")
	# Keep formatting for viewing
	less +G -fr "$tmp"
	;;
	"View last command in a new kitty window")
	sleep 1
	kitty less +G -fr "$tmp"
	;;
	*)
	echo "No action chosen."
	;;
esac

exit 0