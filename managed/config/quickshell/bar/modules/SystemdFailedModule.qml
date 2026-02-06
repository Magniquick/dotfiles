/**
 * @module SystemdFailedModule
 * @description Systemd failed units monitor UI (binds to singleton SystemdFailedService)
 *
 * Features:
 * - Monitors both system and user systemd instances
 * - Real-time failed unit detection via D-Bus monitoring (4 parallel monitors)
 * - Automatic refresh on systemd state changes (750ms debounced)
 * - Displays count of failed units with error indicator
 * - Interactive tooltip listing all failed units
 * - Per-unit controls (restart, stop) via systemctl
 * - Automatic crash recovery for D-Bus monitors (exponential backoff)
 *
 * Monitoring Architecture:
 * - 4 D-Bus monitors running in parallel:
 *   1. System manager state changes (busctl monitor org.freedesktop.systemd1 --system)
 *   2. User manager state changes (busctl monitor org.freedesktop.systemd1 --user)
 *   3. System unit properties (busctl monitor org.freedesktop.systemd1 --system --match)
 *   4. User unit properties (busctl monitor org.freedesktop.systemd1 --user --match)
 * - Unified crash handler for all monitors
 * - Shared restart timer with exponential backoff (1s, 2s, 4s, 8s, up to 30s)
 *
 * Dependencies:
 * - systemctl: List and control systemd units
 * - busctl: D-Bus monitoring for real-time event detection
 * - systemd: System and service manager
 *
 * Configuration:
 * - enableEventRefresh: Enable D-Bus event monitoring (default: true)
 * - eventDebounceMs: Event debounce interval (default: 750ms)
 * - debugLogging: Enable console debug output (default: false)
 *
 * Performance:
 * - Debounced refresh reduces redundant systemctl calls during rapid state changes
 * - Separate system/user monitoring prevents cross-contamination
 * - Property signal batching reduces unnecessary refreshes
 * - Event-driven updates only when state actually changes
 *
 * Failed Unit Detection:
 * - System units: systemctl --failed --no-legend (system-wide services)
 * - User units: systemctl --user --failed --no-legend (user session services)
 * - Combined count displayed in bar
 * - Detailed unit list in tooltip with status and controls
 *
 * Error Handling:
 * - Unified crash handler for all 4 D-Bus monitors
 * - Exponential backoff prevents rapid restart loops
 * - Graceful degradation when busctl unavailable (falls back to polling)
 * - Safe parsing of systemctl output
 * - Console warnings on first crash only
 *
 * Unit Controls:
 * - Restart button: systemctl restart <unit> / systemctl --user restart <unit>
 * - Stop button: systemctl stop <unit> / systemctl --user stop <unit>
 * - Automatic refresh after control action
 *
 * @example
 * // Basic usage with defaults
 * SystemdFailedModule {}
 *
 * @example
 * // Custom debounce and debug logging
 * SystemdFailedModule {
 *     eventDebounceMs: 1000
 *     debugLogging: true
 * }
 *
 * @example
 * // Disable event monitoring (polling only)
 * SystemdFailedModule {
 *     enableEventRefresh: false
 * }
 */
pragma ComponentBehavior: Bound
import ".."
import "../components"
import QtQuick

ModuleContainer {
    id: root

    property bool debugLogging: false
    property bool enableEventRefresh: true
    property int eventDebounceMs: 750
    readonly property int failedCount: SystemdFailedService.failedCount
    readonly property string lastRefreshedLabel: SystemdFailedService.lastRefreshedLabel
    readonly property int systemFailedCount: SystemdFailedService.systemFailedCount
    readonly property var systemFailedUnits: SystemdFailedService.systemFailedUnits
    readonly property int userFailedCount: SystemdFailedService.userFailedCount
    readonly property var userFailedUnits: SystemdFailedService.userFailedUnits

    collapsed: root.failedCount <= 0
    tooltipShowRefreshIcon: true
    tooltipSubtitle: root.lastRefreshedLabel
    tooltipText: root.failedCount > 0 ? (root.failedCount === 1 ? "Failed unit: " : "Failed units: ") + root.failedCount + " (system: " + root.systemFailedCount + ", user: " + root.userFailedCount + ")" : "Failed units: none"
    tooltipTitle: root.failedCount === 1 ? "Failed unit" : "Failed units"

    content: [
        IconTextRow {
            iconColor: Config.color.error
            iconText: ""
            spacing: root.contentSpacing
            text: root.failedCount + (root.failedCount === 1 ? " unit failed" : " units failed")
            textColor: Config.color.error
        }
    ]
    tooltipContent: Component {
        SystemdFailedTooltip {
            systemUnits: root.systemFailedUnits
            userUnits: root.userFailedUnits
            width: 360
        }
    }

    Component.onCompleted: {
        root.tooltipRefreshRequested.connect(function () {
            SystemdFailedService.refreshCounts("manual");
        });
        SystemdFailedService.debugLogging = root.debugLogging;
        SystemdFailedService.enableEventRefresh = root.enableEventRefresh;
        SystemdFailedService.eventDebounceMs = root.eventDebounceMs;
    }

    onDebugLoggingChanged: SystemdFailedService.debugLogging = root.debugLogging
    onEnableEventRefreshChanged: SystemdFailedService.enableEventRefresh = root.enableEventRefresh
    onEventDebounceMsChanged: SystemdFailedService.eventDebounceMs = root.eventDebounceMs
}
