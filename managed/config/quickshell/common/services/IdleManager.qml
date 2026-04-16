import QtQml
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import ".." as Common

Scope {
    id: root

    property bool active: true
    // Honor IdleInhibitor instances (e.g. bar idle inhibit toggle).
    property bool respectInhibitors: true
    readonly property bool sleepInhibited: Common.GlobalState.idleSleepInhibited

    // Display power management.
    property bool monitorSleepEnabled: true
    readonly property real monitorSleepTimeoutSec: Common.GlobalState.idleMonitorSleepTimeoutSec
    property bool dpmsOff: false
    readonly property string currentDesktop: (Quickshell.env("XDG_CURRENT_DESKTOP") || "").toLowerCase()
    readonly property var dpmsCommands: ({
        "hyprland": {
            "on": ["hyprctl", "dispatch", "dpms", "on"],
            "off": ["hyprctl", "dispatch", "dpms", "off"]
        },
        "niri": {
            "on": ["niri", "msg", "action", "power-on-monitors"],
            "off": ["niri", "msg", "action", "power-off-monitors"]
        }
    })

    // Optional long-idle suspend flow.
    readonly property bool suspendEnabled: Common.GlobalState.idleSuspendEnabled
    readonly property real suspendTimeoutSec: Common.GlobalState.idleSuspendTimeoutSec
    property bool lockBeforeSuspend: true
    property var lockCommand: [Quickshell.shellPath("tools/launch-lockscreen.sh")]
    property var suspendCommand: ["systemctl", "suspend"]

    // Lockscreen speedup: idle timeouts fire 3x faster when locked.
    readonly property bool screenLocked: Common.GlobalState.screenLocked
    readonly property real lockSpeedupFactor: 3.0

    // Persist idle settings across restarts.
    readonly property string settingsPath: Quickshell.shellPath("data/idle_settings.json")

    FileView {
        id: settingsFile

        path: root.settingsPath
        blockLoading: true
        atomicWrites: true
    }

    Component.onCompleted: {
        // blockLoading ensures text() is available synchronously here.
        const raw = settingsFile.text();
        if (raw && raw.length > 0) {
            try {
                const data = JSON.parse(raw);
                if (Number.isFinite(data.displayOffTimeoutSec))
                    Common.GlobalState.idleMonitorSleepTimeoutSec = data.displayOffTimeoutSec;
                if (Number.isFinite(data.suspendTimeoutSec))
                    Common.GlobalState.idleSuspendTimeoutSec = data.suspendTimeoutSec;
                if (typeof data.suspendEnabled === "boolean")
                    Common.GlobalState.idleSuspendEnabled = data.suspendEnabled;
            } catch (e) {
                console.warn("[IdleManager] failed to parse settings:", e);
            }
        }
    }

    function saveSettings() {
        const data = {
            displayOffTimeoutSec: Common.GlobalState.idleMonitorSleepTimeoutSec,
            suspendTimeoutSec: Math.round(Common.GlobalState.idleSuspendTimeoutSec),
            suspendEnabled: Common.GlobalState.idleSuspendEnabled
        };
        settingsFile.setText(JSON.stringify(data));
    }

    Connections {
        target: Common.GlobalState

        function onIdleMonitorSleepTimeoutSecChanged() {
            root.saveSettings();
        }

        function onIdleSuspendTimeoutSecChanged() {
            root.saveSettings();
        }

        function onIdleSuspendEnabledChanged() {
            root.saveSettings();
        }
    }

    function run(command) {
        Common.ProcessHelper.execDetached(command);
    }

    function setDpms(on) {
        if (!root.active || !root.monitorSleepEnabled)
            return;

        if (root.dpmsOff === !on)
            return;

        root.dpmsOff = !on;
        if (root.currentDesktop.indexOf("hypr") !== -1) {
            root.run(root.dpmsCommands.hyprland[on ? "on" : "off"]);
            return;
        }
        if (root.currentDesktop.indexOf("niri") !== -1) {
            root.run(root.dpmsCommands.niri[on ? "on" : "off"]);
            return;
        }
    }

    function wake() {
        if (root.dpmsOff)
            root.setDpms(true);
    }

    function triggerSuspend() {
        if (!root.active || !root.suspendEnabled)
            return;

        if (root.lockBeforeSuspend)
            root.run(root.lockCommand);

        root.run(root.suspendCommand);
    }

    onSleepInhibitedChanged: {
        if (sleepInhibited)
            root.wake();
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.active && Common.GlobalState.idleSleepInhibited && Common.GlobalState.idleSleepInhibitUntilMs > 0

        onTriggered: {
            if (Date.now() >= Common.GlobalState.idleSleepInhibitUntilMs) {
                Common.GlobalState.clearSleepInhibit();
                root.wake();
            }
        }
    }

    // DPMS monitor — normal
    IdleMonitor {
        enabled: root.active && !root.sleepInhibited && root.monitorSleepEnabled && root.monitorSleepTimeoutSec > 0 && !root.screenLocked
        respectInhibitors: root.respectInhibitors
        timeout: root.monitorSleepTimeoutSec

        onIsIdleChanged: {
            if (isIdle)
                root.setDpms(false);
            else
                root.wake();
        }
    }

    // DPMS monitor — lockscreen (3x faster)
    IdleMonitor {
        enabled: root.active && !root.sleepInhibited && root.monitorSleepEnabled && root.monitorSleepTimeoutSec > 0 && root.screenLocked
        respectInhibitors: root.respectInhibitors
        timeout: Math.max(1, root.monitorSleepTimeoutSec / root.lockSpeedupFactor)

        onIsIdleChanged: {
            if (isIdle)
                root.setDpms(false);
            else
                root.wake();
        }
    }

    // Suspend monitor — normal
    IdleMonitor {
        enabled: root.active && !root.sleepInhibited && root.suspendEnabled && root.dpmsOff && root.suspendTimeoutSec > 0 && !root.screenLocked
        respectInhibitors: root.respectInhibitors
        timeout: root.suspendTimeoutSec

        onIsIdleChanged: {
            if (isIdle)
                root.triggerSuspend();
            else
                root.wake();
        }
    }

    // Suspend monitor — lockscreen (3x faster)
    IdleMonitor {
        enabled: root.active && !root.sleepInhibited && root.suspendEnabled && root.dpmsOff && root.suspendTimeoutSec > 0 && root.screenLocked
        respectInhibitors: root.respectInhibitors
        timeout: Math.max(1, root.suspendTimeoutSec / root.lockSpeedupFactor)

        onIsIdleChanged: {
            if (isIdle)
                root.triggerSuspend();
            else
                root.wake();
        }
    }
}
