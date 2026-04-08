#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

MICROTEX_BIN_DEFAULTS=(
  "${MICROTEX_BIN:-}"
  "/opt/MicroTeX/LaTeX"
  "/opt/illogical-impulse-microtex-git/LaTeX"
)

print_help() {
  cat <<'EOF'
Usage: ./tools/render-latex.sh [options]

Render a LaTeX expression to SVG using MicroTeX in headless mode.

Input:
  --input TEX          LaTeX source as a literal string
  --input-file PATH    Read LaTeX source from a file
  stdin                If neither option is given, read from stdin

Output:
  --output PATH        Output SVG path (required)

Rendering options:
  --textsize N         Font size in points (default: 20)
  --foreground COLOR   Foreground color (default: black)
  --background COLOR   Background color (default: transparent)
  --padding N          Padding in pixels (default: 8)
  --maxwidth N         Maximum render width in pixels (default: 720)

Environment:
  MICROTEX_BIN         Override the MicroTeX binary path

Examples:
  ./tools/render-latex.sh --input '\sqrt{x^2 + y^2}' --output /tmp/example.svg
  printf '%s\n' '$$E = mc^2$$' | ./tools/render-latex.sh --output /tmp/example.svg
EOF
}

find_microtex_bin() {
  local candidate

  for candidate in "${MICROTEX_BIN_DEFAULTS[@]}"; do
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  if command -v LaTeX >/dev/null 2>&1; then
    command -v LaTeX
    return 0
  fi

  return 1
}

input_text=""
input_file=""
output_path=""
textsize="20"
foreground="black"
background="transparent"
padding="8"
maxwidth="720"

while (($# > 0)); do
  case "$1" in
    --input)
      input_text="${2:?missing value for --input}"
      shift 2
      ;;
    --input-file)
      input_file="${2:?missing value for --input-file}"
      shift 2
      ;;
    --output)
      output_path="${2:?missing value for --output}"
      shift 2
      ;;
    --textsize)
      textsize="${2:?missing value for --textsize}"
      shift 2
      ;;
    --foreground)
      foreground="${2:?missing value for --foreground}"
      shift 2
      ;;
    --background)
      background="${2:?missing value for --background}"
      shift 2
      ;;
    --padding)
      padding="${2:?missing value for --padding}"
      shift 2
      ;;
    --maxwidth)
      maxwidth="${2:?missing value for --maxwidth}"
      shift 2
      ;;
    --help|-h)
      print_help
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n\n' "$1" >&2
      print_help >&2
      exit 2
      ;;
  esac
done

if [[ -z "${output_path}" ]]; then
  printf 'Missing required option: --output\n\n' >&2
  print_help >&2
  exit 2
fi

if [[ -n "${input_text}" && -n "${input_file}" ]]; then
  printf 'Use either --input or --input-file, not both.\n' >&2
  exit 2
fi

if [[ -n "${input_file}" ]]; then
  if [[ ! -f "${input_file}" ]]; then
    printf 'Input file not found: %s\n' "${input_file}" >&2
    exit 1
  fi
  input_text="$(<"${input_file}")"
elif [[ -z "${input_text}" ]]; then
  input_text="$(cat)"
fi

if [[ -z "${input_text}" ]]; then
  printf 'No LaTeX input provided.\n' >&2
  exit 2
fi

if ! microtex_bin="$(find_microtex_bin)"; then
  cat >&2 <<'EOF'
MicroTeX binary not found.

Expected one of:
  - $MICROTEX_BIN
  - /opt/MicroTeX/LaTeX
  - /opt/illogical-impulse-microtex-git/LaTeX
  - LaTeX in PATH

Install MicroTeX first, then rerun this tool.
EOF
  exit 127
fi

mkdir -p "$(dirname "${output_path}")"
output_abs="$(realpath -m "${output_path}")"
microtex_dir="$(cd "$(dirname "${microtex_bin}")" && pwd)"

cmd=(
  "${microtex_bin}"
  -headless
  "-input=${input_text}"
  "-output=${output_abs}"
  "-textsize=${textsize}"
  "-foreground=${foreground}"
  "-background=${background}"
  "-padding=${padding}"
  "-maxwidth=${maxwidth}"
)

(
  cd "${microtex_dir}"
  exec "${cmd[@]}"
)

printf '%s\n' "${output_abs}"
