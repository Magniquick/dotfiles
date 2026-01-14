# Testing Guide

This document provides testing workflows and mock patterns for the Quickshell configuration.

## Overview

Since Quickshell doesn't have automated testing support, all testing is done manually. This guide provides mock command patterns and testing workflows to verify module behavior without requiring actual system state changes.

## Mock Command Patterns

### Network Module (NetworkModule.qml)

**Mock nmcli output:**
```bash
# Create mock nmcli script
cat > /tmp/mock-nmcli <<'EOF'
#!/bin/bash
case "$1" in
  "monitor")
    # Simulate connection events
    sleep 2
    echo "Connectivity is now 'full'"
    sleep 3
    echo "Connectivity is now 'limited'"
    ;;
  "-t" | "-f")
    # Simulate connection status
    echo "eth0:ethernet:connected:Wired connection 1"
    ;;
  "device" | "show")
    # Simulate device details
    echo "GENERAL.DEVICE:                         eth0"
    echo "GENERAL.TYPE:                           ethernet"
    echo "IP4.ADDRESS[1]:                         192.168.1.100/24"
    echo "IP4.GATEWAY:                            192.168.1.1"
    ;;
esac
EOF
chmod +x /tmp/mock-nmcli

# Test with mock
export PATH="/tmp:$PATH"
quickshell -c bar
```

**Expected output format:**
```
<device>:<type>:<state>:<connection-name>
eth0:ethernet:connected:Wired connection 1
wlan0:wifi:connected:MyWiFi
```

### Backlight Module (BacklightModule.qml)

**Mock brillo:**
```bash
# Create mock brillo script
cat > /tmp/mock-brillo <<'EOF'
#!/bin/bash
BRIGHTNESS_FILE="/tmp/mock-brightness"
[[ ! -f "$BRIGHTNESS_FILE" ]] && echo "50" > "$BRIGHTNESS_FILE"

case "$1" in
  "-G")
    cat "$BRIGHTNESS_FILE"
    ;;
  "-S")
    echo "$2" > "$BRIGHTNESS_FILE"
    ;;
  "-A")
    current=$(cat "$BRIGHTNESS_FILE")
    new=$((current + ${2:-1}))
    [[ $new -gt 100 ]] && new=100
    echo "$new" > "$BRIGHTNESS_FILE"
    ;;
  "-U")
    current=$(cat "$BRIGHTNESS_FILE")
    new=$((current - ${2:-1}))
    [[ $new -lt 1 ]] && new=1
    echo "$new" > "$BRIGHTNESS_FILE"
    ;;
esac
EOF
chmod +x /tmp/mock-brillo

# Mock sysfs files
mkdir -p /tmp/mock-sysfs/backlight/intel_backlight
echo "100" > /tmp/mock-sysfs/backlight/intel_backlight/max_brightness
echo "50" > /tmp/mock-sysfs/backlight/intel_backlight/actual_brightness

# Test with mock
export PATH="/tmp:$PATH"
# Update backlightDevice property to use /tmp/mock-sysfs path
```

**Mock udevadm monitor:**
```bash
# Create mock udevadm script
cat > /tmp/mock-udevadm <<'EOF'
#!/bin/bash
if [[ "$1" == "monitor" ]]; then
  while true; do
    sleep 2
    echo "KERNEL[123.456] change   /devices/pci0000:00/backlight/intel_backlight (backlight)"
    echo "UDEV  [123.457] change   /devices/pci0000:00/backlight/intel_backlight (backlight)"
  done
fi
EOF
chmod +x /tmp/mock-udevadm
```

### Privacy Module (PrivacyModule.qml)

**Mock privacy_dots.sh output:**
```bash
# Create mock privacy script
cat > /tmp/mock-privacy.sh <<'EOF'
#!/bin/bash
# Simulate rotating privacy states
states=(
  '{"mic":0,"cam":0,"loc":0,"scr":0,"mic_app":"","cam_app":"","loc_app":"","scr_app":""}'
  '{"mic":1,"cam":0,"loc":0,"scr":0,"mic_app":"firefox","cam_app":"","loc_app":"","scr_app":""}'
  '{"mic":1,"cam":1,"loc":0,"scr":0,"mic_app":"firefox","cam_app":"zoom","loc_app":"","scr_app":""}'
  '{"mic":1,"cam":1,"loc":1,"scr":0,"mic_app":"firefox","cam_app":"zoom","loc_app":"geoclue","scr_app":""}'
  '{"mic":1,"cam":1,"loc":1,"scr":1,"mic_app":"firefox","cam_app":"zoom","loc_app":"geoclue","scr_app":"obs"}'
)
index=$(( (RANDOM % ${#states[@]}) ))
echo "${states[$index]}"
EOF
chmod +x /tmp/mock-privacy.sh

# Update scriptPath property to use /tmp/mock-privacy.sh
```

**Expected JSON format:**
```json
{
  "mic": 0|1,
  "cam": 0|1,
  "loc": 0|1,
  "scr": 0|1,
  "mic_app": "app1, app2, ...",
  "cam_app": "app1, app2, ...",
  "loc_app": "app1, app2, ...",
  "scr_app": "app1, app2, ..."
}
```

### Systemd Failed Module (SystemdFailedModule.qml)

**Mock systemctl:**
```bash
# Create mock systemctl script
cat > /tmp/mock-systemctl <<'EOF'
#!/bin/bash
if [[ "$*" == *"--failed"* ]]; then
  # Simulate failed units
  cat <<UNITS
nginx.service          loaded failed failed    NGINX Web Server
postgresql.service     loaded failed failed    PostgreSQL Database
docker.service         loaded failed failed    Docker Application Container Engine
UNITS
fi
EOF
chmod +x /tmp/mock-systemctl

# Test with mock
export PATH="/tmp:$PATH"
quickshell -c bar
```

**Mock busctl monitor:**
```bash
# Create mock busctl script
cat > /tmp/mock-busctl <<'EOF'
#!/bin/bash
if [[ "$1" == "monitor" ]]; then
  while true; do
    sleep 5
    echo 'signal sender=:1.1 interface=org.freedesktop.systemd1.Manager member=JobRemoved'
    sleep 3
    echo 'signal sender=:1.1 interface=org.freedesktop.systemd1.Manager member=UnitNew'
  done
fi
EOF
chmod +x /tmp/mock-busctl
```

### Notification Module (NotificationModule.qml)

**Mock swaync-client:**
```bash
# Create mock swaync-client script
cat > /tmp/mock-swaync-client <<'EOF'
#!/bin/bash
if [[ "$*" == *"-swb"* ]]; then
  # Watch mode - output JSON status updates
  states=(
    '{"class":"notification","alt":"notification","tooltip":"3 notifications"}'
    '{"class":"none","alt":"none","tooltip":"No notifications"}'
    '{"class":"dnd-notification","alt":"dnd-notification","tooltip":"DND: 2 notifications"}'
    '{"class":"dnd-none","alt":"dnd-none","tooltip":"DND: No notifications"}'
  )
  while true; do
    for state in "${states[@]}"; do
      echo "$state"
      sleep 3
    done
  done
fi
EOF
chmod +x /tmp/mock-swaync-client

# Test with mock
export PATH="/tmp:$PATH"
quickshell -c bar
```

**Expected JSON format:**
```json
{
  "class": "notification|none|dnd-notification|dnd-none",
  "alt": "notification|none|dnd-notification|dnd-none",
  "tooltip": "descriptive text"
}
```

### Updates Module (UpdatesModule.qml)

**Mock waybar-module-pacman-updates:**
```bash
# Create mock updates script
cat > /tmp/mock-updates <<'EOF'
#!/bin/bash
# Simulate update stream
counts=(0 5 12 23 8 2)
while true; do
  for count in "${counts[@]}"; do
    if [[ $count -eq 0 ]]; then
      echo '{"text":"","alt":"idle","tooltip":"System up to date","class":"idle","percentage":""}'
    else
      echo "{\"text\":\"$count\",\"alt\":\"$count\",\"tooltip\":\"$count updates available\",\"class\":\"$count\",\"percentage\":\"\"}"
    fi
    sleep 10
  done
done
EOF
chmod +x /tmp/mock-updates

# Update updateCommand property to use /tmp/mock-updates
```

## Testing Workflows

### 1. Module Initialization Test

**Goal:** Verify modules load without errors and display correct initial state.

**Steps:**
1. Start quickshell: `quickshell -c bar`
2. Check console for errors/warnings
3. Verify all modules appear in bar
4. Check that modules with command dependencies show appropriate fallback state

**Expected Results:**
- No QML errors in console
- All modules visible or hidden based on availability
- Console warnings for missing dependencies (if any)
- Modules show "unavailable" or disabled state gracefully

### 2. Tooltip Interaction Test

**Goal:** Verify tooltips open, display correctly, and interactive elements work.

**Steps:**
1. Hover over each module icon
2. Verify tooltip appears within 200ms
3. For `tooltipHoverable: true` modules:
   - Move mouse into tooltip
   - Verify tooltip stays open
   - Click sliders/buttons
   - Verify controls work
4. Move mouse away
5. Verify tooltip closes

**Expected Results:**
- Tooltips anchor correctly above module icons
- No tooltip clipping or positioning issues
- Hoverable tooltips remain open during interaction
- Non-hoverable tooltips close immediately on mouse exit
- Interactive controls respond to input

### 3. Debounce and Performance Test

**Goal:** Verify debouncing works and CPU usage remains low.

**Steps:**
1. Start quickshell: `quickshell -c bar`
2. Monitor CPU: `pidstat -p $(pgrep -n quickshell) 1 5`
3. For BacklightModule:
   - Hold brightness key for 3 seconds
   - Check CPU usage during adjustment
   - Release key and wait 1 second
   - Verify final brightness is accurate
4. For NetworkModule:
   - Open tooltip
   - Verify traffic graphs update
   - Close tooltip
   - Verify polling stops
5. For SystemdFailedModule:
   - Trigger systemd state change
   - Verify refresh debounces (750ms)
   - Check console for refresh count

**Expected Results:**
- Idle CPU: ~0%
- During brightness adjustment: <5% CPU
- Final brightness value correct after rapid changes
- Network traffic polling only when tooltip open
- SystemdFailedModule refreshes once per 750ms window

### 4. Crash Recovery Test

**Goal:** Verify modules automatically recover from process crashes.

**Steps:**
1. Start quickshell
2. Find long-running process PIDs:
   ```bash
   ps aux | grep -E "nmcli monitor|udevadm monitor|busctl monitor|swaync-client"
   ```
3. Kill one process: `kill <PID>`
4. Check console for crash warning
5. Wait 1-2 seconds
6. Verify process restarts automatically
7. Kill process again
8. Verify exponential backoff (2s, 4s, 8s, etc.)

**Expected Results:**
- Console warning on first crash: "attempting restart"
- Process restarts within 1s
- Second crash triggers 2s backoff
- Third crash triggers 4s backoff
- Module continues functioning after recovery
- No rapid restart loops

### 5. Scrolling Tooltip Test (Priority 4.2)

**Goal:** Verify tooltip scrolling works when content exceeds maximum height.

**Steps:**
1. Open a tooltip with long content (e.g., SystemdFailedModule with many failed units)
2. Verify scrollbar appears on right side
3. Scroll with mouse wheel
4. Verify gradient fade overlay appears at bottom
5. Scroll to bottom
6. Verify fade overlay disappears
7. Check that `autoScroll` scrolls to show new content

**Expected Results:**
- ScrollIndicator appears only when content exceeds height
- Gradient fade overlay visible when more content below
- Smooth scrolling with mouse wheel
- Auto-scroll to bottom when new content added (if enabled)

### 6. ActionChip Feedback Test (Priority 4.3)

**Goal:** Verify ActionChip visual feedback on clicks.

**Steps:**
1. Open tooltip with ActionChips (e.g., BacklightModule presets)
2. Click a preset button (e.g., "50%")
3. Observe flash animation
4. Test loading state:
   - Set `loading: true` on a chip
   - Verify spinner appears and rotates
   - Set `loading: false`
   - Verify spinner fades out

**Expected Results:**
- Flash animation on every click (brief highlight)
- Spinner appears smoothly when loading
- Spinner rotates continuously
- Smooth fade out when loading completes

### 7. Command Availability Test

**Goal:** Verify graceful degradation when commands unavailable.

**Steps:**
1. Rename command temporarily: `sudo mv /usr/bin/brillo /usr/bin/brillo.bak`
2. Restart quickshell
3. Check BacklightModule:
   - Verify console warning: "brillo not found in PATH"
   - Verify module shows disabled/unavailable state
   - Verify slider/buttons are disabled
4. Restore command: `sudo mv /usr/bin/brillo.bak /usr/bin/brillo`
5. Reload quickshell
6. Verify module works normally

**Expected Results:**
- Console warning on startup when command missing
- Module displays graceful "unavailable" state
- No crashes or QML errors
- Interactive elements properly disabled
- Module recovers after command restored

## Manual Testing Checklist

Use this checklist when testing a full quickshell session:

- [ ] Bar loads without QML errors
- [ ] All modules visible or gracefully hidden
- [ ] No console errors during idle (30s observation)
- [ ] CPU usage <1% when idle
- [ ] Tooltips open and close correctly
- [ ] Hoverable tooltips stay open during interaction
- [ ] Non-hoverable tooltips close on mouse exit
- [ ] Interactive controls respond (sliders, buttons)
- [ ] Scrolling works in long tooltips
- [ ] ActionChip flash animation on click
- [ ] Command availability checks working
- [ ] Process crash recovery functioning
- [ ] Debouncing reduces redundant operations
- [ ] Network polling only when tooltip open
- [ ] Brightness changes respond accurately
- [ ] Privacy indicators update in real-time
- [ ] Systemd failed count updates on changes
- [ ] Notification status updates from SwayNC
- [ ] MPRIS player controls respond correctly

## Common Issues and Solutions

### Issue: High Idle CPU Usage

**Symptoms:** CPU usage >1% when bar is idle

**Check:**
1. Animations running in hidden windows
2. Polling intervals too aggressive
3. Process monitors running without gating

**Solution:**
- Gate animations with window visibility: `running: root.QsWindow.window && root.QsWindow.window.visible`
- Increase polling intervals
- Add debouncing to high-frequency events

### Issue: Module Shows "Unavailable" Despite Command Present

**Symptoms:** Module disabled even though command exists

**Check:**
1. Command in PATH: `command -v <cmd>`
2. Execute permissions: `ls -l $(which <cmd>)`
3. Console warnings from availability check

**Solution:**
- Verify command path
- Check file permissions
- Test command manually
- Review CommandRunner error output

### Issue: Tooltip Doesn't Stay Open

**Symptoms:** Tooltip closes immediately when moving mouse into it

**Check:**
1. `tooltipHoverable` property set correctly
2. `hoverable` passed to TooltipPopup

**Solution:**
- Set `tooltipHoverable: true` on ModuleContainer
- Verify ModuleContainer passes property to TooltipPopup

### Issue: Process Monitor Crashes Repeatedly

**Symptoms:** Console spam with restart warnings

**Check:**
1. Command syntax correct
2. Required permissions (e.g., udevadm may need permissions)
3. Process exits immediately after start

**Solution:**
- Test command manually in terminal
- Check stderr output from process
- Verify all command arguments correct
- Check system logs for permission denials

## Environment Variables for Testing

Some modules support environment variable overrides for testing:

```bash
# Privacy module
export JQ=/tmp/mock-jq
export PW_DUMP=/tmp/mock-pw-dump

# Network module
export PATH="/tmp/mock-bin:$PATH"

# CommandRunner
# See Config.commands pattern (Priority 6.1) when implemented
```

## Performance Benchmarking

### CPU Usage Measurement

```bash
# Start quickshell
quickshell -c bar &
QS_PID=$!

# Wait for stabilization
sleep 20

# Measure idle CPU (should be ~0%)
pidstat -p $QS_PID 1 5 | awk '/Average:/{print "Idle CPU:", $8"%"}'

# Trigger activity (e.g., hold brightness key)
# Measure active CPU (should be <5%)
pidstat -p $QS_PID 1 5 | awk '/Average:/{print "Active CPU:", $8"%"}'
```

### Memory Usage

```bash
ps -p $(pgrep -n quickshell) -o rss,vsz,cmd
```

### Process Monitor Count

```bash
# Count child processes (should match expected monitors)
pstree -p $(pgrep -n quickshell) | grep -oE '\([0-9]+\)' | wc -l
```

## Conclusion

This guide provides comprehensive testing patterns for the Quickshell configuration. While automated tests aren't available, these manual workflows and mock patterns enable thorough verification of module behavior, error handling, and performance characteristics.

When adding new modules or modifying existing ones, follow these testing workflows to ensure:
- Graceful error handling
- Efficient resource usage
- Correct visual feedback
- Proper crash recovery
- Accurate data display
