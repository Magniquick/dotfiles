import QtQml
import Quickshell
import Quickshell.Wayland
import ".." as Common

Scope {
    id: root

    // Master toggle.
    property bool enabled: true
    // Honor IdleInhibitor instances (e.g. bar idle inhibit toggle).
    property bool respectInhibitors: true
    readonly property bool sleepInhibited: Common.GlobalState.idleSleepInhibited

    // Display power management.
    property bool monitorSleepEnabled: true
    property real monitorSleepTimeoutSec: 300
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
    property bool suspendEnabled: false
    property real suspendTimeoutSec: 1800
    property bool lockBeforeSuspend: true
    property var lockCommand: [Quickshell.shellPath("tools/launch-lockscreen.sh")]
    property var suspendCommand: ["systemctl", "suspend"]

    function run(command) {
        Common.ProcessHelper.execDetached(command);
    }

    function setDpms(on) {
        if (!root.enabled || !root.monitorSleepEnabled)
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
        if (!root.enabled || !root.suspendEnabled)
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
        running: root.enabled && Common.GlobalState.idleSleepInhibited && Common.GlobalState.idleSleepInhibitUntilMs > 0

        onTriggered: {
            if (Date.now() >= Common.GlobalState.idleSleepInhibitUntilMs) {
                Common.GlobalState.clearSleepInhibit();
                root.wake();
            }
        }
    }

    IdleMonitor {
        enabled: root.enabled && !root.sleepInhibited && root.monitorSleepEnabled && root.monitorSleepTimeoutSec > 0
        respectInhibitors: root.respectInhibitors
        timeout: root.monitorSleepTimeoutSec

        onIsIdleChanged: {
            if (isIdle)
                root.setDpms(false);
            else
                root.wake();
        }
    }

    IdleMonitor {
        enabled: root.enabled && !root.sleepInhibited && root.suspendEnabled && root.dpmsOff && root.suspendTimeoutSec > 0
        respectInhibitors: root.respectInhibitors
        timeout: root.suspendTimeoutSec

        onIsIdleChanged: {
            if (isIdle)
                root.triggerSuspend();
            else
                root.wake();
        }
    }
}
