# Tooltip Hoverable Guidelines

This document provides guidelines for when to use `tooltipHoverable` in the Quickshell configuration.

## What is `tooltipHoverable`?

The `tooltipHoverable` property on `ModuleContainer` controls whether a tooltip stays open when the user hovers over it. When enabled, the tooltip can contain interactive elements like sliders, buttons, and links that users can click.

## When to Use `tooltipHoverable: true`

Use `tooltipHoverable: true` when your tooltip contains **interactive elements** that users need to click or manipulate:

### ✓ Interactive Controls
- **Sliders**: Volume controls, brightness sliders, etc.
  - Example: `BacklightModule`, `MprisModule`
- **Buttons/ActionChips**: Quick action buttons (e.g., "20%", "50%", "80%", "100%" brightness presets)
  - Example: `BacklightModule` brightness presets
- **Links**: Browser links or clickable items
  - Example: Tooltips with `showBrowserIcon: true`
- **Text Selection**: Long text that users might want to copy
  - Example: Network interface details, error messages

### ✓ Complex Layouts Needing Scrolling
- **Long Lists**: When content exceeds `maximumHeight` and scrolling is needed
  - Example: Long notification lists, many failed systemd units
- **Multiple Sections**: Content organized into collapsible sections or tabs

### Module Examples Using `tooltipHoverable: true`

```qml
// BacklightModule - slider + action buttons
ModuleContainer {
    tooltipHoverable: true  // Users need to interact with slider and preset buttons
    tooltipContent: Component {
        ColumnLayout {
            LevelSlider { /* interactive slider */ }
            TooltipActionsRow {
                ActionChip { text: "20%" }
                ActionChip { text: "50%" }
                // ...
            }
        }
    }
}

// MprisModule - seekbar + playback controls
ModuleContainer {
    tooltipHoverable: true  // Users need to seek and control playback
    tooltipContent: Component {
        ColumnLayout {
            LevelSlider { /* seekbar */ }
            RowLayout {
                ActionButtonBase { /* previous button */ }
                ActionButtonBase { /* play/pause button */ }
                ActionButtonBase { /* next button */ }
            }
        }
    }
}
```

## When to Use `tooltipHoverable: false` (Default)

Use `tooltipHoverable: false` (or omit the property) when your tooltip is **purely informational** with no interactive elements:

### ✓ Read-Only Information
- **Status Display**: Current state, statistics, or metrics
  - Example: `NetworkModule` (just shows connection info)
- **Static Text**: Labels, descriptions, explanations
  - Example: `BatteryModule` (charge percentage and time remaining)
- **Icons Only**: Visual indicators without interaction
  - Example: `PrivacyModule` (shows which sensors are active)

### ✓ Simple Lists
- **Fixed Lists**: Short, non-scrollable lists that don't need interaction
  - Example: WiFi network name and signal strength

### Module Examples Using `tooltipHoverable: false`

```qml
// NetworkModule - display only
ModuleContainer {
    // tooltipHoverable: false is default, no need to specify
    tooltipContent: Component {
        ColumnLayout {
            Text { text: "Network: Connected" }
            Text { text: "Interface: eth0" }
            InfoRow { label: "Speed"; value: "1000 Mbps" }
        }
    }
}

// BatteryModule - display only
ModuleContainer {
    tooltipContent: Component {
        ColumnLayout {
            Text { text: "Battery: 85%" }
            Text { text: "Time remaining: 4:32" }
            Text { text: "Status: Charging" }
        }
    }
}
```

## Decision Tree

Use this decision tree to determine if you need `tooltipHoverable: true`:

```
Does your tooltip contain any of these?
├─ Sliders (LevelSlider)? ─────────────────→ YES → use tooltipHoverable: true
├─ Buttons (ActionChip, ActionButtonBase)? ─→ YES → use tooltipHoverable: true
├─ Links (showBrowserIcon: true)? ─────────→ YES → use tooltipHoverable: true
├─ Text users might want to copy? ─────────→ YES → use tooltipHoverable: true
├─ Scrollable content (maximumHeight)? ────→ YES → use tooltipHoverable: true
└─ None of the above? ─────────────────────→ NO  → use tooltipHoverable: false (default)
```

## Common Mistakes

### ❌ Don't Enable Hoverable for Display-Only Tooltips
```qml
// BAD: No interactive elements, don't need hoverable
ModuleContainer {
    tooltipHoverable: true  // ← Unnecessary!
    tooltipContent: Component {
        Text { text: "Just displaying info" }
    }
}
```

### ❌ Don't Forget Hoverable When Adding Interactive Elements
```qml
// BAD: Has interactive slider but forgot tooltipHoverable
ModuleContainer {
    // Missing: tooltipHoverable: true
    tooltipContent: Component {
        LevelSlider {
            onUserChanged: value => {
                // User can't interact with this!
            }
        }
    }
}
```

### ✓ Correct Usage
```qml
// GOOD: Interactive slider with hoverable enabled
ModuleContainer {
    tooltipHoverable: true  // ← Required for slider interaction
    tooltipContent: Component {
        LevelSlider {
            onUserChanged: value => {
                // User can now interact with this
            }
        }
    }
}
```

## Implementation Details

### How It Works
When `tooltipHoverable: true`:
1. `ModuleContainer` passes `hoverable: true` to `TooltipPopup`
2. `TooltipPopup` sets up a `HoverHandler` on the popup body
3. Tooltip stays open as long as: `open || pinned || (hoverable && popupHovered)`
4. User can move mouse into tooltip and interact with elements

### Performance Considerations
- Hoverable tooltips remain in memory while open (for interaction)
- Non-hoverable tooltips can be simpler and more lightweight
- Only enable hoverable when actually needed

## Scrolling Support

As of the scrolling implementation (Priority 4.2), tooltips can now have:
- `maximumHeight`: Limit tooltip height (triggers scrolling when content exceeds this)
- `autoScroll`: Automatically scroll to show new content
- `showScrollIndicator`: Display scroll indicator when scrolling is available

### Scrolling + Hoverable
When using scrolling, you typically want `tooltipHoverable: true` so users can scroll:

```qml
ModuleContainer {
    tooltipHoverable: true  // Needed to interact with scroll
    tooltipContent: Component {
        ColumnLayout {
            // maximumHeight is set on TooltipPopup automatically based on screen size
            Repeater {
                model: 50  // Many items
                Text { text: `Item ${index}` }
            }
        }
    }
}
```

## Summary

- **Use `tooltipHoverable: true`** for interactive tooltips (sliders, buttons, links, scrollable content)
- **Use `tooltipHoverable: false`** (or omit) for display-only tooltips
- When in doubt, ask: "Does the user need to click or interact with anything in this tooltip?"
  - Yes → `tooltipHoverable: true`
  - No → `tooltipHoverable: false`
