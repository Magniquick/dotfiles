/**
 * @module SystemdFailedModule
 * @description Systemd failed units monitor UI (binds to singleton SystemdFailedService)
 *
 * Features:
 * - Monitors both system and user systemd instances
 * - Refreshes from a qs-go provider on startup, manually, and on systemd D-Bus events
 * - Displays count of failed units with error indicator
 * - Interactive tooltip listing all failed units
 * - Per-unit controls (restart, stop) via systemctl
 *
 * Dependencies:
 * - systemctl: List and control systemd units
 * - systemd: System and service manager
 *
 * Configuration:
 * - debugLogging: Enable console debug output (default: false)
 *
 * Performance:
 * - Event-driven refresh avoids fixed-interval sampling
 *
 * Failed Unit Detection:
 * - qs-go snapshots system/user failed units from structured systemctl JSON
 * - systemd D-Bus manager signals trigger debounced refreshes
 * - Combined count displayed in bar
 * - Detailed unit list in tooltip with status and controls
 *
 * Error Handling:
 * - Provider exposes snapshot errors through SystemdFailedService.error
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
 * // Custom debug logging
 * SystemdFailedModule {
 *     debugLogging: true
 * }
 *
 */
pragma ComponentBehavior: Bound
import ".."
import "../components"
import QtQuick

ModuleContainer {
    id: root

    property bool debugLogging: false
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

    // Keep service config declarative so it stays in sync without imperative
    // signal handlers.
    Binding {
        target: SystemdFailedService
        property: "debugLogging"
        value: root.debugLogging
    }
    Component.onCompleted: {
        root.tooltipRefreshRequested.connect(function () {
            SystemdFailedService.refreshCounts("manual");
        });
    }
}
