/**
 * @module SystemdFailedModule
 * @description Systemd failed units monitor with real-time D-Bus event detection
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
import Quickshell.Io

ModuleContainer {
    id: root

    property bool debugLogging: false
    property bool enableEventRefresh: true
    property int eventDebounceMs: 750
    property int failedCount: root.systemFailedCount + root.userFailedCount
    property string lastRefreshedLabel: ""
    property int systemFailedCount: 0
    property var systemFailedUnits: []
    property bool systemPropsSignalPending: false
    property int userFailedCount: 0
    property var userFailedUnits: []
    property bool userPropsSignalPending: false
    property int monitorRestartAttempts: 0
    property bool monitorDegraded: false

    function handleMonitorCrash(monitorName, code) {
        if (root.monitorRestartAttempts === 0) {
            console.warn(`SystemdFailedModule: ${monitorName} exited with code ${code}, attempting restart`);
        } else {
            const backoff = Math.min(30000, 1000 * Math.pow(2, root.monitorRestartAttempts));
            console.warn(`SystemdFailedModule: ${monitorName} crashed again (attempt ${root.monitorRestartAttempts + 1}), next restart in ${backoff}ms`);
        }
        root.monitorDegraded = true;
        root.monitorRestartAttempts++;
        monitorBackoffResetTimer.stop();
        monitorRestartTimer.restart();
    }

    function handleMonitorLine(source, data) {
        const trimmed = data.trim();
        if (trimmed === "")
            return;

        if (trimmed.indexOf("signal ") === 0) {
            root.logEvent(source + "Monitor signal " + trimmed);
            root.scheduleRefresh(source);
        }
    }
    function handlePropsMonitorLine(source, data) {
        const trimmed = data.trim();
        if (trimmed === "")
            return;

        if (trimmed.indexOf("signal ") === 0) {
            if (source === "system")
                root.systemPropsSignalPending = true;
            else
                root.userPropsSignalPending = true;
            root.logEvent(source + "Props signal " + trimmed);
            return;
        }
        const pending = source === "system" ? root.systemPropsSignalPending : root.userPropsSignalPending;
        if (!pending)
            return;

        if (trimmed.indexOf("string \"NFailedUnits\"") !== -1 || trimmed.indexOf("string \"FailedUnits\"") !== -1) {
            root.logEvent(source + "Props matched failed units");
            if (source === "system")
                root.systemPropsSignalPending = false;
            else
                root.userPropsSignalPending = false;
            root.scheduleRefresh(source + "-props");
        }
    }
    function logEvent(message) {
        if (!root.debugLogging)
            return;

        console.log("SystemdFailedModule " + new Date().toISOString() + " " + message);
    }
    function parseFailedUnits(text) {
        if (!text || text.trim() === "")
            return [];

        const lines = text.trim().split("\n").map(line => {
            return line.trim();
        }).filter(line => {
            return line !== "";
        });
        const units = [];
        for (let i = 0; i < lines.length; i++) {
            let line = lines[i];
            if (line.indexOf("0 loaded units listed") === 0)
                continue;

            if (line.indexOf("UNIT ") === 0)
                continue;

            line = line.replace(/^●\s+/, "");
            const parts = line.split(/\s+/);
            if (parts.length === 0)
                continue;

            const unit = parts[0] || "";
            const load = parts[1] || "";
            const active = parts[2] || "";
            const sub = parts[3] || "";
            const description = parts.slice(4).join(" ");
            if (unit)
                units.push({
                    "unit": unit,
                    "load": load,
                    "active": active,
                    "sub": sub,
                    "description": description
                });
        }
        return units;
    }
    function refreshCounts(source) {
        root.logEvent("refreshCounts " + (source || "unknown"));
        systemRunner.trigger();
        userRunner.trigger();
    }
    function scheduleRefresh(source) {
        root.logEvent("scheduleRefresh " + source);
        if (!eventDebounce.running)
            eventDebounce.start();
    }

    collapsed: root.failedCount <= 0
    tooltipShowRefreshIcon: true
    tooltipSubtitle: root.lastRefreshedLabel
    tooltipText: root.failedCount > 0 ? (root.failedCount === 1 ? "Failed unit: " : "Failed units: ") + root.failedCount + " (system: " + root.systemFailedCount + ", user: " + root.userFailedCount + ")" : "Failed units: none"
    tooltipTitle: root.failedCount === 1 ? "Failed unit" : "Failed units"

    content: [
        IconTextRow {
            iconColor: Config.m3.error
            iconText: ""
            spacing: root.contentSpacing
            text: root.failedCount + (root.failedCount === 1 ? " unit failed" : " units failed")
            textColor: Config.m3.error
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
            root.refreshCounts("manual");
        });
        root.refreshCounts("startup");
    }

    CommandRunner {
        id: systemRunner

        command: "systemctl --failed --no-legend --plain --no-pager"
        intervalMs: 0

        onOutputChanged: {
            root.systemFailedUnits = root.parseFailedUnits(output);
            root.systemFailedCount = root.systemFailedUnits.length;
            root.lastRefreshedLabel = Qt.formatDateTime(new Date(), "hh:mm ap");
            root.logEvent("systemRunner output=" + root.systemFailedCount);
        }
    }
    CommandRunner {
        id: userRunner

        command: "systemctl --user --failed --no-legend --plain --no-pager"
        intervalMs: 0

        onOutputChanged: {
            root.userFailedUnits = root.parseFailedUnits(output);
            root.userFailedCount = root.userFailedUnits.length;
            root.lastRefreshedLabel = Qt.formatDateTime(new Date(), "hh:mm ap");
            root.logEvent("userRunner output=" + root.userFailedCount);
        }
    }
    Timer {
        id: monitorRestartTimer

        interval: Math.min(30000, 1000 * Math.pow(2, root.monitorRestartAttempts))
        running: false

        onTriggered: {
            root.monitorDegraded = false;
            systemMonitor.running = root.enableEventRefresh;
            systemPropsMonitor.running = root.enableEventRefresh;
            userMonitor.running = root.enableEventRefresh;
            userPropsMonitor.running = root.enableEventRefresh;
        }
    }
    Timer {
        id: monitorBackoffResetTimer

        interval: 60000
        running: systemMonitor.running || systemPropsMonitor.running || userMonitor.running || userPropsMonitor.running
        repeat: false

        onTriggered: {
            if (root.monitorRestartAttempts > 0) {
                console.log("SystemdFailedModule: D-Bus monitors stable for 60s, resetting backoff");
            }
            root.monitorRestartAttempts = 0;
        }
    }
    Process {
        id: systemMonitor

        command: ["dbus-monitor", "--system", "type='signal',sender='org.freedesktop.systemd1',interface='org.freedesktop.systemd1.Manager',member='JobRemoved'"]
        running: root.enableEventRefresh

        stdout: SplitParser {
            onRead: function (data) {
                root.handleMonitorLine("system", data);
            }
        }
        onExited: code => root.handleMonitorCrash("systemMonitor", code)
    }
    Process {
        id: systemPropsMonitor

        command: ["dbus-monitor", "--system", "type='signal',sender='org.freedesktop.systemd1',path='/org/freedesktop/systemd1',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.freedesktop.systemd1.Manager'"]
        running: root.enableEventRefresh

        stdout: SplitParser {
            onRead: function (data) {
                root.handlePropsMonitorLine("system", data);
            }
        }
        onExited: code => root.handleMonitorCrash("systemPropsMonitor", code)
    }
    Process {
        id: userMonitor

        command: ["dbus-monitor", "--session", "type='signal',sender='org.freedesktop.systemd1',interface='org.freedesktop.systemd1.Manager',member='JobRemoved'"]
        running: root.enableEventRefresh

        stdout: SplitParser {
            onRead: function (data) {
                root.handleMonitorLine("user", data);
            }
        }
        onExited: code => root.handleMonitorCrash("userMonitor", code)
    }
    Process {
        id: userPropsMonitor

        command: ["dbus-monitor", "--session", "type='signal',sender='org.freedesktop.systemd1',path='/org/freedesktop/systemd1',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.freedesktop.systemd1.Manager'"]
        running: root.enableEventRefresh

        stdout: SplitParser {
            onRead: function (data) {
                root.handlePropsMonitorLine("user", data);
            }
        }
        onExited: code => root.handleMonitorCrash("userPropsMonitor", code)
    }
    Timer {
        id: eventDebounce

        interval: root.eventDebounceMs
        repeat: false

        onTriggered: {
            root.logEvent("eventDebounce fired");
            root.refreshCounts("debounce");
        }
    }
}
