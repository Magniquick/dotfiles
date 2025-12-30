import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls

ShellRoot {
    id: root

    readonly property var palette: ColorPalette.palette
    property string powermenuHover: ""
    property string powermenuSelection: ""
    property bool powermenuVisible: true

    function onButton(action) {
        if (powermenuSelection === action) {
            powermenuVisible = false;
            runAction(action);
            resetState();
            Qt.quit();
        } else {
            powermenuSelection = action;
        }
    }
    function resetState() {
        powermenuSelection = "";
        powermenuHover = "";
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
    Powermenu {
        id: powermenu

        colors: palette
        hoverAction: powermenuHover
        selection: powermenuSelection
        targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        visible: powermenuVisible

        onActionInvoked: actionName => onButton(actionName)
        onHoverUpdated: actionName => powermenuHover = actionName
        onRequestClose: {
            powermenuVisible = false;
            resetState();
            Qt.quit();
        }
    }
}
