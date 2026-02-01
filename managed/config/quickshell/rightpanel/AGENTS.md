# Repository Guidelines

This file provides guidance for working with code in this module (rightpanel).

## Architecture

### Entry Point Flow

`shell.qml` → `RightPanel.qml` → notification components

- **shell.qml**: Window management via `ShellRoot` + `Loader`. Uses `HyprlandFocusGrab` to capture focus when visible; clicking outside closes the panel via `GlobalState.rightPanelVisible`.
- **RightPanel.qml**: Main notification center with D-Bus `NotificationServer` integration and dual-window system (main panel + popup overlay).

### Notification Data Flow

```
D-Bus NotificationServer
    → onNotification signal
    → notificationStore.addNotification()
    → NotificationEntry created with Timer
    → list/popupList arrays updated
    → ListView observes changes
```

**NotificationEntry** (inline component): Holds notification state including `notificationId`, `notification` reference, `popup` flag, `timer`, and derived properties (`appName`, `title`, `body`, `urgency`, `iconSource`).

**notificationStore** (QtObject): Central state manager with methods:
- `addNotification(notification)` – Creates entry, starts urgency-based timeout
- `dismissNotification(id)` – Removes from lists, calls `notification.dismiss()`
- `dismissAll()` – Clears everything
- `timeoutNotification(id)` – Moves popup to history (or dismisses if transient)

### Timeout Logic

Urgency-based popup timeouts (matching dunst config):
- Critical: 0 (no timeout)
- Normal: 8000ms
- Low: 3000ms

Notifications can override via `expireTimeout` (-1 = use default, 0 = never, >0 = use value).

### Dual Window System

1. **Main panel** (420px wide): Full notification list anchored top-right with gaps
2. **Popup overlay** (320px, max 560px height): Transient popups at `WlrLayer.Overlay`

Both windows use separate `WlrLayershell.namespace` values for compositor identification.

### Component Hierarchy

```
components/
├── NotificationCard.qml      # List item: frame + content + dismiss handling
├── NotificationContent.qml   # Rich renderer: icons, body, actions, inline reply
├── NotificationFrame.qml     # Styled container with click-through
├── ActionButton.qml          # Reusable button primitive
└── PopupNotification.qml     # Popup variant (simpler, no source button)
```

**NotificationContent** handles:
- App-specific icon overrides (WhatsApp, BatWatch, Kitty, OpenAI)
- WhatsApp link detection → brand color `#25D366`
- Circular app icon masking via `OpacityMask`
- Action buttons with icon resolution
- Inline reply field for compatible notifications
- Source inspector (debug view showing all notification fields)

### Server Health Monitoring

A 10-second `Timer` runs `busctl --user status org.freedesktop.Notifications`. If the server crashes (exit code != 0), the `NotificationServer` loader is toggled to restart it.

## Key Patterns

**Visibility-controlled loading**: The main panel uses `Loader { active: GlobalState.rightPanelVisible }` to avoid rendering when hidden.

**Popup visibility**: `popupWindow.visible` is bound to `popupContent.opacity > 0.01` to account for fade animations.

**Image existence check**: `NotificationContent` spawns a `Process` to run `test -f` on image paths before displaying.

## Testing Checklist

- Clicking outside panel or pressing Escape closes it
- Popup appears at top-right, fades out after timeout
- Critical notifications persist until dismissed
- Action buttons invoke notification actions
- Inline reply works for apps that support it
- Source inspector (code icon) shows raw notification data
