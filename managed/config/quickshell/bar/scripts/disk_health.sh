#!/usr/bin/env bash

set -euo pipefail

mode="health"
device="/dev/nvme0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wear)
      mode="wear"
      ;;
    *)
      device="$1"
      ;;
  esac
  shift
done

if ! command -v smartctl >/dev/null 2>&1; then
  echo "Unknown (smartctl missing)"
  exit 0
fi

if [[ "$mode" == "wear" ]]; then
  wear_level=$(sudo smartctl --attributes "$device" 2>/dev/null | awk -F': *' '/^Percentage Used:/ {print $2; exit}' || true)
  echo "${wear_level:-Unknown}"
  exit 0
fi

critical_warning=$(sudo smartctl --attributes "$device" 2>/dev/null | awk -F': *' '/^Critical Warning:/ {print $2; exit}' || true)
health_result=$(sudo smartctl --health --tolerance=conservative "$device" 2>/dev/null | awk -F': *' '/result/ {print $2; exit}' || true)

critical_warning=${critical_warning:-unknown}
health_result=${health_result:-unknown}

if [[ "$critical_warning" == "0x00" && "$health_result" == "PASSED" ]]; then
  echo "Healthy"
elif [[ "$health_result" != "unknown" ]]; then
  echo "$health_result (${critical_warning})"
else
  echo "Unknown (${critical_warning})"
fi
