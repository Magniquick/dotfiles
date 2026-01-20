#!/usr/bin/env bash

# CPU Usage
cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

# Memory Usage
mem_total=$(free -m | awk '/Mem:/ {print $2}')
mem_used=$(free -m | awk '/Mem:/ {print $3}')
mem_pct=$((100 * mem_used / mem_total))
mem_used_label=$(awk -v used="$mem_used" 'BEGIN { printf "%.1fGB", used/1024 }')
mem_total_label=$(awk -v total="$mem_total" 'BEGIN { printf "%.1fGB", total/1024 }')

# Disk Usage (Root) and static disk health (cached)
disk_pct=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
script_dir=$(dirname "$0")
cache_dir="${XDG_CACHE_HOME:-/tmp}/quickshell"
cache_file="$cache_dir/disk_health.cache"
mkdir -p "$cache_dir"

if [ -f "$cache_file" ]; then
	read -r cached_health cached_wear <"$cache_file"
else
	cached_health=$("$script_dir/disk_health.sh" 2>/dev/null | tr -d '\\n')
	cached_wear=$("$script_dir/disk_health.sh" --wear 2>/dev/null | tr -d '\\n')
	printf "%s %s" "$cached_health" "$cached_wear" >"$cache_file"
fi

disk_health="$cached_health"
disk_wear="$cached_wear"

# Temperature (assuming amdgpu or coretemp)
temp=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -n1 | awk '{print $1/1000}')
if [ -z "$temp" ]; then temp=0; fi

# Uptime
uptime_str=$(uptime -p | sed 's/up //')

# PSI (Pressure Stall Information) - avg10 values (10-second averages)
# "some" = at least one task stalled, "full" = all tasks stalled
psi_cpu_some=0
psi_cpu_full=0
psi_mem_some=0
psi_mem_full=0
psi_io_some=0
psi_io_full=0
if [ -f /proc/pressure/cpu ]; then
	psi_cpu_some=$(awk '/^some/ {gsub(/.*avg10=/,""); gsub(/ .*/,""); print}' /proc/pressure/cpu)
	psi_cpu_full=$(awk '/^full/ {gsub(/.*avg10=/,""); gsub(/ .*/,""); print}' /proc/pressure/cpu)
fi
if [ -f /proc/pressure/memory ]; then
	psi_mem_some=$(awk '/^some/ {gsub(/.*avg10=/,""); gsub(/ .*/,""); print}' /proc/pressure/memory)
	psi_mem_full=$(awk '/^full/ {gsub(/.*avg10=/,""); gsub(/ .*/,""); print}' /proc/pressure/memory)
fi
if [ -f /proc/pressure/io ]; then
	psi_io_some=$(awk '/^some/ {gsub(/.*avg10=/,""); gsub(/ .*/,""); print}' /proc/pressure/io)
	psi_io_full=$(awk '/^full/ {gsub(/.*avg10=/,""); gsub(/ .*/,""); print}' /proc/pressure/io)
fi

echo "{\"cpu\": $cpu_usage, \"mem\": $mem_pct, \"mem_used\": \"${mem_used_label}\", \"mem_total\": \"${mem_total_label}\", \"disk\": $disk_pct, \"disk_health\": \"${disk_health}\", \"disk_wear\": \"${disk_wear}\", \"temp\": $temp, \"uptime\": \"$uptime_str\", \"psi_cpu_some\": $psi_cpu_some, \"psi_cpu_full\": $psi_cpu_full, \"psi_mem_some\": $psi_mem_some, \"psi_mem_full\": $psi_mem_full, \"psi_io_some\": $psi_io_some, \"psi_io_full\": $psi_io_full}"
