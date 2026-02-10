#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
disk-io-rate.sh [interval_seconds] [samples]

Print disk I/O throughput (and IOPS) for the block device backing "/".

Args:
  interval_seconds  Delay between samples (default: 1)
  samples           Number of samples to print (default: 0 = infinite)

Notes:
  - Reads /proc/diskstats and computes deltas.
  - Resolves "/" SOURCE to a whole-disk device via lsblk PKNAME chain.
EOF
}

interval="${1:-1}"
samples="${2:-0}"

if [[ "${interval}" == "-h" || "${interval}" == "--help" ]]; then
  usage
  exit 0
fi

root_src="$(findmnt -n -o SOURCE -T / 2>/dev/null || true)"
if [[ -z "${root_src}" ]]; then
  root_src="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
fi

if [[ -z "${root_src}" ]]; then
  echo "error: could not determine root mount source" >&2
  exit 1
fi

# Some filesystems (e.g. btrfs subvols) include suffixes like: /dev/nvme0n1p6[/@]
root_src="${root_src%%[*}"

if [[ "${root_src}" != /dev/* ]]; then
  echo "error: root mount source is not a /dev block device: ${root_src}" >&2
  exit 1
fi

resolve_whole_disk_name() {
  local dev="$1"
  # Canonicalize partitions (/dev/disk/by-uuid/... -> /dev/nvme0n1p2)
  dev="$(readlink -f "$dev" 2>/dev/null || echo "$dev")"

  while true; do
    local pk
    pk="$(lsblk -no PKNAME "$dev" 2>/dev/null | head -n1 | tr -d '[:space:]' || true)"
    if [[ -z "${pk}" ]]; then
      local name
      name="$(lsblk -no NAME "$dev" 2>/dev/null | head -n1 | tr -d '[:space:]' || true)"
      if [[ -n "${name}" ]]; then
        printf '%s\n' "${name}"
        return 0
      fi
      # Fall back to basename of /dev/ path.
      printf '%s\n' "${dev##*/}"
      return 0
    fi
    dev="/dev/${pk}"
  done
}

disk_name="$(resolve_whole_disk_name "${root_src}")"

read_diskstats_row() {
  local name="$1"
  # major minor name reads_completed reads_merged sectors_read ms_reading writes_completed writes_merged sectors_written ms_writing ...
  awk -v d="$name" '$3==d {print $4, $6, $8, $10; exit}' /proc/diskstats
}

human_bps() {
  local bps="$1"
  awk -v b="$bps" 'BEGIN{
    split("B/s KB/s MB/s GB/s TB/s", u, " ");
    i=1;
    while (b>=1024 && i<5) { b/=1024; i++; }
    if (i==1) printf "%.0f %s", b, u[i];
    else if (b>=100) printf "%.0f %s", b, u[i];
    else if (b>=10) printf "%.1f %s", b, u[i];
    else printf "%.2f %s", b, u[i];
  }'
}

echo "root_source=${root_src}"
echo "disk=${disk_name}"

prev="$(read_diskstats_row "${disk_name}" || true)"
if [[ -z "${prev}" ]]; then
  echo "error: could not find ${disk_name} in /proc/diskstats" >&2
  exit 1
fi

prev_rio="$(awk '{print $1}' <<<"$prev")"
prev_rsec="$(awk '{print $2}' <<<"$prev")"
prev_wio="$(awk '{print $3}' <<<"$prev")"
prev_wsec="$(awk '{print $4}' <<<"$prev")"

i=0
while true; do
  sleep "${interval}"
  cur="$(read_diskstats_row "${disk_name}" || true)"
  if [[ -z "${cur}" ]]; then
    echo "error: could not find ${disk_name} in /proc/diskstats" >&2
    exit 1
  fi

  cur_rio="$(awk '{print $1}' <<<"$cur")"
  cur_rsec="$(awk '{print $2}' <<<"$cur")"
  cur_wio="$(awk '{print $3}' <<<"$cur")"
  cur_wsec="$(awk '{print $4}' <<<"$cur")"

  drio=$(( cur_rio - prev_rio ))
  dwio=$(( cur_wio - prev_wio ))
  drsec=$(( cur_rsec - prev_rsec ))
  dwsec=$(( cur_wsec - prev_wsec ))

  # /proc/diskstats sectors are 512-byte units.
  drbytes=$(( drsec * 512 ))
  dwbytes=$(( dwsec * 512 ))

  # Use awk for float division.
  read_bps="$(awk -v b="$drbytes" -v s="$interval" 'BEGIN{ if (s<=0) print 0; else printf "%.0f", b/s }')"
  write_bps="$(awk -v b="$dwbytes" -v s="$interval" 'BEGIN{ if (s<=0) print 0; else printf "%.0f", b/s }')"
  read_iops="$(awk -v n="$drio" -v s="$interval" 'BEGIN{ if (s<=0) print 0; else printf "%.1f", n/s }')"
  write_iops="$(awk -v n="$dwio" -v s="$interval" 'BEGIN{ if (s<=0) print 0; else printf "%.1f", n/s }')"

  ts="$(date +%H:%M:%S)"
  echo "${ts}  read=$(human_bps "$read_bps") (${read_iops} iops)  write=$(human_bps "$write_bps") (${write_iops} iops)"

  prev_rio="$cur_rio"
  prev_rsec="$cur_rsec"
  prev_wio="$cur_wio"
  prev_wsec="$cur_wsec"

  if [[ "${samples}" != "0" ]]; then
    i=$(( i + 1 ))
    if (( i >= samples )); then
      break
    fi
  fi
done
