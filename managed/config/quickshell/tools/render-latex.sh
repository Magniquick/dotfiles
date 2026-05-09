#!/usr/bin/env bash
set -euo pipefail

RATEX_BIN_DEFAULTS=(
  "${RATEX_RENDER_SVG_BIN:-}"
  "${CARGO_HOME:-$HOME/.local/share/cargo}/bin/render-svg"
  "$HOME/.local/share/cargo/bin/render-svg"
  "$HOME/.cargo/bin/render-svg"
)

print_help() {
  cat <<'EOF'
Usage: ./tools/render-latex.sh [options]

Render a LaTeX math expression to SVG using RaTeX render-svg.

Input:
  --input TEX          LaTeX source as a literal string
  --input-file PATH    Read LaTeX source from a file
  stdin                If neither option is given, read from stdin

Output:
  --output PATH        Output SVG path (required)

Rendering options:
  --textsize N         Font size in points (default: 20)
  --foreground COLOR   Foreground color (default: black)
  --dpr N              Device pixel ratio for the generated SVG (default: 1)
  --inline             Render with inline math style

Environment:
  RATEX_RENDER_SVG_BIN Override the render-svg binary path

Examples:
  ./tools/render-latex.sh --input '\sqrt{x^2 + y^2}' --output /tmp/example.svg
  printf '%s\n' '$$E = mc^2$$' | ./tools/render-latex.sh --output /tmp/example.svg
EOF
}

find_ratex_bin() {
  local candidate

  if command -v render-svg >/dev/null 2>&1; then
    command -v render-svg
    return 0
  fi

  for candidate in "${RATEX_BIN_DEFAULTS[@]}"; do
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

strip_math_delimiters() {
  local text="$1"
  local length="${#text}"

  if [[ "${text}" == \$\$* && "${text}" == *\$\$ && "${length}" -ge 4 ]]; then
    printf '%s\n' "${text:2:length-4}"
  elif [[ "${text}" == \$* && "${text}" == *\$ && "${length}" -ge 2 ]]; then
    printf '%s\n' "${text:1:length-2}"
  elif [[ "${text}" == "\\("* && "${text}" == *"\\)" && "${length}" -ge 4 ]]; then
    printf '%s\n' "${text:2:length-4}"
  elif [[ "${text}" == "\\["* && "${text}" == *"\\]" && "${length}" -ge 4 ]]; then
    printf '%s\n' "${text:2:length-4}"
  else
    printf '%s\n' "${text}"
  fi
}

input_text=""
input_file=""
output_path=""
textsize="20"
foreground="black"
dpr="1"
inline=false

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
    --dpr)
      dpr="${2:?missing value for --dpr}"
      shift 2
      ;;
    --inline)
      inline=true
      shift
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

if ! ratex_bin="$(find_ratex_bin)"; then
  cat >&2 <<'EOF'
render-svg not found.

Install RaTeX first:
  cargo install ratex-svg --bin render-svg --features 'cli embed-fonts'
EOF
  exit 127
fi

output_abs="$(realpath -m "${output_path}")"
mkdir -p "$(dirname "${output_abs}")"

tmp_dir="$(mktemp -d)"
stdout_file="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -rf "${tmp_dir}" "${stdout_file}" "${stderr_file}"' EXIT

cmd=(
  "${ratex_bin}"
  --output-dir "${tmp_dir}"
  --font-size "${textsize}"
  --dpr "${dpr}"
  --color "${foreground}"
)

if [[ "${inline}" == true ]]; then
  cmd=( "${cmd[@]}" --inline )
fi

formula="$(strip_math_delimiters "${input_text}")"
status=0
printf '%s\n' "${formula}" | "${cmd[@]}" >"${stdout_file}" 2>"${stderr_file}" || status=$?

if [[ "${status}" -ne 0 || ! -s "${tmp_dir}/0001.svg" ]]; then
  cat "${stderr_file}" >&2
  cat "${stdout_file}" >&2
  if [[ "${status}" -ne 0 ]]; then
    exit "${status}"
  fi
  exit 1
fi

cp "${tmp_dir}/0001.svg" "${output_abs}"
printf '%s\n' "${output_abs}"
