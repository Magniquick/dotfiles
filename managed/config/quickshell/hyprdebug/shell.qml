import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    property int pendingProcesses: 1

    function dump(label, value) {
        let text = "";
        try {
            text = typeof value === "string" ? value : JSON.stringify(value, null, 2);
        } catch (err) {
            text = String(value);
        }
        console.log(`[hyprdebug] ${label}: ${text}`);
    }

    function finishOne() {
        pendingProcesses -= 1;
        if (pendingProcesses <= 0)
            Qt.quit();
    }

    Component.onCompleted: {
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
        startTimer.start();
    }

    Timer {
        id: startTimer

        interval: 250
        repeat: false
        running: false

        onTriggered: {
            root.dump("focusedMonitor", Hyprland.focusedMonitor ? Hyprland.focusedMonitor.lastIpcObject : null);
            root.dump("focusedWorkspace", Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.lastIpcObject : null);
            root.dump("activeToplevel", Hyprland.activeToplevel ? Hyprland.activeToplevel.lastIpcObject : null);
            root.dump("toplevels", Hyprland.toplevels && Hyprland.toplevels.values
                ? Hyprland.toplevels.values.map(toplevel => toplevel && toplevel.lastIpcObject ? toplevel.lastIpcObject : null)
                : []);
            root.dump("workspaces", Hyprland.workspaces && Hyprland.workspaces.values
                ? Hyprland.workspaces.values.map(workspace => workspace && workspace.lastIpcObject ? workspace.lastIpcObject : null)
                : []);
            if (Hyprland.focusedMonitor && Hyprland.focusedMonitor.activeWorkspace)
                root.dump("focusedMonitor.activeWorkspace.toplevels.length", Hyprland.focusedMonitor.activeWorkspace.toplevels.values.length);
            layersProcess.running = true;
        }
    }

    Process {
        id: layersProcess

        command: ["hyprctl", "layers", "-j"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.dump("hyprctl layers", this.text)
        }
        // qmllint disable signal-handler-parameters
        onExited: {
            root.finishOne();
        }
        // qmllint enable signal-handler-parameters
    }

}
