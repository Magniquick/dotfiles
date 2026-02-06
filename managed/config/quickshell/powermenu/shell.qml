import Quickshell
import Quickshell.Hyprland
import QtQuick
import "common" as Common

ShellRoot {
    id: root

    readonly property var colors: Common.Config.color
    property string powermenuHover: ""
    property string powermenuSelection: ""
    property bool powermenuVisible: true

    function onButton(action) {
        if (root.powermenuSelection === action) {
            root.powermenuVisible = false;
            runAction(action);
            resetState();
            Qt.quit();
        } else {
            root.powermenuSelection = action;
        }
    }
    function resetState() {
        root.powermenuSelection = "";
        root.powermenuHover = "";
    }
    function runAction(action) {
        var cmd = [];
        if (action === "Poweroff")
            cmd = ["systemctl", "poweroff"];
        else if (action === "Reboot")
            cmd = ["systemctl", "reboot"];
        else if (action === "Suspend")
            cmd = ["systemctl", "suspend"];
        else if (action === "Hibernate")
            cmd = ["systemctl", "hibernate"];
        else if (action === "Exit")
            cmd = ["loginctl", "lock-session"];
        else if (action === "Windows")
            cmd = ["systemctl", "reboot", "--boot-loader-entry=auto-windows"];

        if (cmd.length === 0)
            return;
        Quickshell.execDetached(cmd);
    }

    function resolveFocusedScreen() {
        const monitor = Hyprland.focusedMonitor;
        if (monitor && monitor.name) {
            for (const s of Quickshell.screens) {
                if (s.name === monitor.name)
                    return s;
            }
        }
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    Powermenu {
        id: powermenu

        colors: root.colors
        hoverAction: root.powermenuHover
        selection: root.powermenuSelection
        targetScreen: root.resolveFocusedScreen()
        visible: root.powermenuVisible

        onActionInvoked: actionName => root.onButton(actionName)
        onHoverUpdated: actionName => root.powermenuHover = actionName
        onRequestClose: {
            root.powermenuVisible = false;
            root.resetState();
            Qt.quit();
        }
    }
}
