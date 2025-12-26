import QtQuick
import QtQml
import Quickshell
import Quickshell.Io

import "bar" as Bar
import "powermenu" as Powermenu

ShellRoot {
    LoggingCategory {
        name: "quickshell.dbus.properties"
        defaultLogLevel: LoggingCategory.Critical
    }

    Variants {
        model: Quickshell.screens
        delegate: Bar.BarWindow {}
    }

    property bool powermenuVisible: false
    property string powermenuSelection: ""
    property string powermenuHover: ""

    readonly property var powermenuPalette: ColorPalette.palette

    function resetPowermenuState() {
        powermenuSelection = "";
        powermenuHover = "";
    }

    function togglePowermenu() {
        const next = !powermenuVisible;
        if (next)
            resetPowermenuState();
        powermenuVisible = next;
        if (!next)
            resetPowermenuState();
    }

    function runPowermenuAction(action) {
        let cmd = [];
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
        powermenuActionProcess.command = cmd;
        powermenuActionProcess.running = true;
    }

    function onPowermenuButton(action) {
        if (powermenuSelection === action) {
            powermenuVisible = false;
            runPowermenuAction(action);
            resetPowermenuState();
        } else {
            powermenuSelection = action;
        }
    }

    Process {
        id: powermenuActionProcess
        running: false
    }

    IpcHandler {
        target: "powermenu"
        function toggle(): void {
            togglePowermenu();
        }
        function show(): void {
            powermenuVisible = true;
            resetPowermenuState();
        }
        function hide(): void {
            powermenuVisible = false;
            resetPowermenuState();
        }
    }

    Powermenu.Powermenu {
        id: powermenu
        visible: powermenuVisible
        targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        colors: powermenuPalette
        selection: powermenuSelection
        hoverAction: powermenuHover
        onRequestClose: {
            powermenuVisible = false;
            resetPowermenuState();
        }
        onActionInvoked: actionName => onPowermenuButton(actionName)
        onHoverUpdated: actionName => powermenuHover = actionName
    }

    LazyLoader {
        id: hyprquickshotLoader
        loading: false
        source: "hyprquickshot/shell.qml"
    }

    function ensureHyprquickshotLoaded() {
        if (!hyprquickshotLoader.loading)
            hyprquickshotLoader.loading = true;
    }

    IpcHandler {
        target: "hyprquickshot"
        function toggle(): void {
            ensureHyprquickshotLoaded();
            if (hyprquickshotLoader.item && hyprquickshotLoader.item.toggleActive)
                hyprquickshotLoader.item.toggleActive();
        }
        function show(): void {
            ensureHyprquickshotLoaded();
            if (hyprquickshotLoader.item && hyprquickshotLoader.item.activate)
                hyprquickshotLoader.item.activate();
        }
        function hide(): void {
            ensureHyprquickshotLoaded();
            if (hyprquickshotLoader.item && hyprquickshotLoader.item.deactivate)
                hyprquickshotLoader.item.deactivate();
        }
    }
}
