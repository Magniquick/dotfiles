# Quickshell Configuration TODO

Generated: 2026-01-10

## Remaining Tasks

None - all tasks complete!

---

## Metrics

- **Total QML Files**: 62
- **Module Files**: 24 (~4,600 lines)
- **Component Files**: 21
- **Long-running Processes**: 6 instances across 4 modules (all with crash recovery)
- **CommandRunner Usage**: 13+ instances (all with error handling)
- **Animation Instances**: ~50+ (properly gated)
- **External Dependencies**: nmcli, systemctl, brillo, swaync-client, pw-dump, udevadm, jq, fuser

---

## Done

### 1.1 CommandRunner Error Handling
- stderr capture, onError signal, errorOutput property, timeout support

### 1.2 Process Crash Recovery
- All 4 modules (NetworkModule, NotificationModule, SystemdFailedModule, BacklightModule)
- Exponential backoff (1s→30s max), 60s stability reset

### 1.3 MPRIS Animation Gating
- Window visibility check on marquee animation

### 2.1 NetworkModule Polling Optimization
- Cache, debounce, nmcli monitor integration

### 2.2 BacklightModule Debouncing
- ACTION=change filter, 150ms debounce (bypassed when tooltip open)

### 2.3 TooltipPopup Animation Leak Fix
- alwaysRunToEnd: false

### 3.1 DependencyCheck Singleton
- Centralized availability checking with notify-send alerts

### 3.2 LevelSlider Config Constants
- Config.slider.barHeight, knobSize, knobWidth

### 3.3 ToDoModule Consolidation
- Removed duplicate files, using Rust-based todoist-api

### 3.4 privacy_dots.sh Error Handling
- JSON validation, error payloads, missing dep detection

### 3.5 Powermenu Palette Fix
- ColorPalette.palette reference corrected

### 4.1 MPRIS Seek Improvements
- Seek preview tooltip, unavailable indicator, dragEnded signal, current/total time display

### 4.2 Tooltip Scrolling
- Flickable wrapper, ScrollIndicator, maximumHeight property

### 4.3 ActionChip Visual Feedback
- Flash animation, loading spinner

### 4.4 Tooltip Hoverable
- Modules with interactive content (sliders, buttons) correctly set tooltipHoverable: true

### 5.2 TESTING.md Documentation
- Mock command patterns, stub scripts, expected output formats

### 6.1 Centralized Dependency Injection [SKIPPED]
- Decided against as over-engineering

### 6.2 CommandRunner Improvements
- Timeout property added
- dragEnded signal for debounced slider actions (used in MPRIS seek)

### ModuleContainer Click Handler
- Added clicked signal and TapHandler
- MprisModule: click to toggle play/pause

### 5.1 Module Documentation
- All 24 modules now have JSDoc headers with description, features, and dependencies
