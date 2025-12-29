import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
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
            iconColor: Config.red
            iconText: ""
            spacing: root.contentSpacing
            text: root.failedCount + (root.failedCount === 1 ? " unit failed" : " units failed")
            textColor: Config.red
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
    Process {
        id: systemMonitor

        command: ["dbus-monitor", "--system", "type='signal',sender='org.freedesktop.systemd1',interface='org.freedesktop.systemd1.Manager',member='JobRemoved'"]
        running: root.enableEventRefresh

        stdout: SplitParser {
            onRead: function (data) {
                root.handleMonitorLine("system", data);
            }
        }
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
