pragma ComponentBehavior: Bound
//@ pragma UseQApplication
import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

import "bar" as Bar
import "leftpanel" as LeftPanel
import "lockscreen" as Lockscreen
import "overview" as Overview
import "powermenu" as PowerMenu
import "rightpanel" as RightPanel
import "common/services" as CommonServices

ShellRoot {
    id: shellRoot

    readonly property string lockscreenLauncher: Quickshell.shellPath("tools/launch-lockscreen.sh")

    Component.onCompleted: Quickshell.watchFiles = false

    CommonServices.IdleManager {}
    Lockscreen.LockController {
        onLockedChanged: Bar.GlobalState.screenLocked = locked
    }
    IpcHandler {
        target: "dev"

        function reload() {
            Quickshell.reload(false);
        }

        function reloadHard() {
            Quickshell.reload(true);
        }
    }
    IpcHandler {
        target: "leftpanel"

        function open() {
            Bar.GlobalState.powermenuVisible = false;
            Bar.GlobalState.overviewVisible = false;
            Bar.GlobalState.leftPanelVisible = true;
        }

        function close() {
            Bar.GlobalState.leftPanelVisible = false;
        }

        function toggle() {
            Bar.GlobalState.toggleLeftPanel();
        }

        function status(): string {
            return JSON.stringify({
                visible: Bar.GlobalState.leftPanelVisible,
                animating: shellRoot.leftPanelAnimating,
                windowVisible: leftPanelWindow.visible
            });
        }

        function expandLatestTool(): bool {
            return leftPanel && leftPanel.setLatestVisibleToolExpanded
                ? leftPanel.setLatestVisibleToolExpanded(true)
                : false;
        }

        function collapseLatestTool(): bool {
            return leftPanel && leftPanel.setLatestVisibleToolExpanded
                ? leftPanel.setLatestVisibleToolExpanded(false)
                : false;
        }
    }
    IpcHandler {
        target: "hyprquickshot"

        function open() {
            Bar.GlobalState.setHyprQuickshotVisible(true);
            if (Bar.GlobalState.hyprQuickshotController && typeof Bar.GlobalState.hyprQuickshotController.activate === "function" && !Bar.GlobalState.hyprQuickshotController.active)
                Bar.GlobalState.hyprQuickshotController.activate();
        }

        function toggle() {
            if (Bar.GlobalState.hyprQuickshotController && typeof Bar.GlobalState.hyprQuickshotController.toggleActive === "function") {
                Bar.GlobalState.hyprQuickshotController.toggleActive();
                return;
            }
            Bar.GlobalState.toggleHyprQuickshot();
        }

        function stop() {
            Bar.GlobalState.stopScreenRecording();
        }

        function status(): string {
            return JSON.stringify({
                active: Bar.GlobalState.screenRecordingActive,
                audioDevice: Bar.GlobalState.screenRecordingAudioDevice,
                audioMode: Bar.GlobalState.screenRecordingAudioMode,
                filePath: Bar.GlobalState.screenRecordingPath,
                pid: Bar.GlobalState.screenRecordingPid,
                state: Bar.GlobalState.screenRecordingState,
                visible: Bar.GlobalState.hyprQuickshotVisible
            });
        }

        function setMode(modeValue: string): bool {
            if (!Bar.GlobalState.hyprQuickshotController || typeof Bar.GlobalState.hyprQuickshotController.debugSetMode !== "function")
                return false;
            if (!Bar.GlobalState.hyprQuickshotController.active)
                Bar.GlobalState.hyprQuickshotController.activate();
            return Bar.GlobalState.hyprQuickshotController.debugSetMode(modeValue);
        }

        function refreshWindows(): string {
            if (!Bar.GlobalState.hyprQuickshotController || typeof Bar.GlobalState.hyprQuickshotController.debugRefreshWindows !== "function")
                return "{}";
            if (!Bar.GlobalState.hyprQuickshotController.active)
                Bar.GlobalState.hyprQuickshotController.activate();
            return Bar.GlobalState.hyprQuickshotController.debugRefreshWindows();
        }

        function snapshotState(): string {
            if (!Bar.GlobalState.hyprQuickshotController || typeof Bar.GlobalState.hyprQuickshotController.debugSnapshotStateJson !== "function")
                return "{}";
            return Bar.GlobalState.hyprQuickshotController.debugSnapshotStateJson();
        }

        function startSnapshotProbe(): bool {
            if (!Bar.GlobalState.hyprQuickshotController || typeof Bar.GlobalState.hyprQuickshotController.debugStartSnapshotProbe !== "function")
                return false;
            Bar.GlobalState.hyprQuickshotController.debugStartSnapshotProbe();
            return true;
        }

        function refreshSnapshot(): bool {
            if (!Bar.GlobalState.hyprQuickshotController || typeof Bar.GlobalState.hyprQuickshotController.debugRefreshSnapshot !== "function")
                return false;
            Bar.GlobalState.hyprQuickshotController.debugRefreshSnapshot();
            return true;
        }

        function stopSnapshotProbe(): bool {
            if (!Bar.GlobalState.hyprQuickshotController || typeof Bar.GlobalState.hyprQuickshotController.debugStopSnapshotProbe !== "function")
                return false;
            Bar.GlobalState.hyprQuickshotController.debugStopSnapshotProbe();
            return true;
        }

        function debugState(): string {
            if (!Bar.GlobalState.hyprQuickshotController || typeof Bar.GlobalState.hyprQuickshotController.debugStateJson !== "function")
                return "{}";
            return Bar.GlobalState.hyprQuickshotController.debugStateJson();
        }

        function captureWindow(stableId: string): string {
            if (!Bar.GlobalState.hyprQuickshotController || typeof Bar.GlobalState.hyprQuickshotController.debugCaptureWindow !== "function")
                return "";
            if (!Bar.GlobalState.hyprQuickshotController.active)
                Bar.GlobalState.hyprQuickshotController.activate();
            return Bar.GlobalState.hyprQuickshotController.debugCaptureWindow(stableId);
        }

        function captureStatus(): string {
            if (!Bar.GlobalState.hyprQuickshotController || typeof Bar.GlobalState.hyprQuickshotController.debugCaptureStatusJson !== "function")
                return "{}";
            return Bar.GlobalState.hyprQuickshotController.debugCaptureStatusJson();
        }

        function debugHistory(): string {
            if (!Bar.GlobalState.hyprQuickshotController || typeof Bar.GlobalState.hyprQuickshotController.debugStateJson !== "function")
                return "[]";
            const state = JSON.parse(Bar.GlobalState.hyprQuickshotController.debugStateJson());
            return JSON.stringify(state.debugEventHistory || []);
        }
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
            cmd = [shellRoot.lockscreenLauncher];
        else if (action === "Windows")
            cmd = ["systemctl", "reboot", "--boot-loader-entry=auto-windows"];

        if (cmd.length === 0)
            return;
        Quickshell.execDetached(cmd);
    }

    function resolvePowermenuScreen() {
        const monitor = Hyprland.focusedMonitor;
        if (monitor && monitor.name) {
            for (const s of Quickshell.screens) {
                if (s.name === monitor.name)
                    return s;
            }
        }
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    LoggingCategory {
        defaultLogLevel: LoggingCategory.Critical
        name: "quickshell.dbus.properties"
    }
    Variants {
        model: Quickshell.screens
        delegate: Bar.BarWindow {}
    }
    Overview.Overview {}
    LazyLoader {
        id: powermenuLoader

        loading: true

        PowerMenu.Powermenu {
            colors: Bar.Config.color
            hoverAction: Bar.GlobalState.powermenuHover
            selection: Bar.GlobalState.powermenuSelection
            targetScreen: shellRoot.resolvePowermenuScreen()
            visible: Bar.GlobalState.powermenuVisible

            onActionInvoked: actionName => {
                if (Bar.GlobalState.powermenuSelection === actionName) {
                    Bar.GlobalState.resetPowermenu();
                    shellRoot.runPowermenuAction(actionName);
                } else {
                    Bar.GlobalState.powermenuSelection = actionName;
                }
            }
            onHoverUpdated: actionName => Bar.GlobalState.powermenuHover = actionName
            onRequestClose: Bar.GlobalState.resetPowermenu()
        }
    }
    LazyLoader {
        id: hyprQuickshotLoader

        active: Bar.GlobalState.hyprQuickshotVisible
            || Bar.GlobalState.screenRecordingActive
            || Bar.GlobalState.screenRecordingState !== "idle"

        source: Qt.resolvedUrl("hyprquickshot/HyprQuickshot.qml")
    }

    // Track left panel visibility with animation state
    property bool leftPanelAnimating: false
    property bool leftPanelShouldShow: Bar.GlobalState.leftPanelVisible

    onLeftPanelShouldShowChanged: {
        leftPanelAnimating = true;
        if (leftPanelShouldShow) {
            leftFocusGrab.active = true;
        } else {
            // Clear text focus early to avoid Wayland text-input surface churn while sliding out.
            if (leftPanelRoot && leftPanelRoot.clearTextFocus)
                leftPanelRoot.clearTextFocus();
        }
    }

    HyprlandFocusGrab {
        id: leftFocusGrab
        windows: [leftPanelWindow]
        onCleared: Bar.GlobalState.leftPanelVisible = false
    }

    PanelWindow {
        id: leftPanelWindow

        readonly property int panelWidth: 380

        color: "transparent"
        visible: shellRoot.leftPanelShouldShow || shellRoot.leftPanelAnimating
        screen: Bar.GlobalState.leftPanelScreen ? Bar.GlobalState.leftPanelScreen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

        anchors {
            top: true
            left: true
            bottom: true
        }
        implicitWidth: panelWidth + Bar.Config.outerGaps

        WlrLayershell.namespace: "quickshell:leftpanel"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0

        Shortcut {
            context: Qt.ApplicationShortcut
            enabled: leftPanelWindow.visible
            sequence: "Escape"
            onActivated: Bar.GlobalState.leftPanelVisible = false
        }

        Item {
            id: leftPanelContainer
            y: Bar.Config.outerGaps
            width: leftPanelWindow.panelWidth
            height: parent.height - Bar.Config.outerGaps * 2

            x: Bar.GlobalState.leftPanelVisible ? Bar.Config.outerGaps : -leftPanelWindow.panelWidth - Bar.Config.outerGaps

            Behavior on x {
                NumberAnimation {
                    id: leftPanelSlide
                    duration: Bar.Config.motion.duration.medium
                    easing.type: Bar.GlobalState.leftPanelVisible ? Easing.OutCubic : Easing.InCubic
                    onRunningChanged: {
                        if (!running) {
                            shellRoot.leftPanelAnimating = false;
                            if (!Bar.GlobalState.leftPanelVisible) {
                                leftFocusGrab.active = false;
                            } else {
                                // Only focus once the open animation has settled.
                                Qt.callLater(function() {
                                    if (Bar.GlobalState.leftPanelVisible && leftPanelRoot && leftPanelRoot.focusComposer)
                                        leftPanelRoot.focusComposer();
                                });
                            }
                        }
                    }
                }
            }

            LeftPanel.LeftPanel {
                id: leftPanelRoot
                anchors.fill: parent
            }
        }
    }

    // Track right panel visibility with animation state
    property bool rightPanelAnimating: false
    property bool rightPanelShouldShow: Bar.GlobalState.rightPanelVisible

    onRightPanelShouldShowChanged: {
        rightPanelAnimating = true;
        if (rightPanelShouldShow) {
            rightFocusGrab.active = true;
        }
    }

    HyprlandFocusGrab {
        id: rightFocusGrab
        windows: [rightPanelWindow]
        onCleared: Bar.GlobalState.rightPanelVisible = false
    }

    PanelWindow {
        id: rightPanelWindow

        readonly property int panelWidth: 420

        color: "transparent"
        visible: shellRoot.rightPanelShouldShow || shellRoot.rightPanelAnimating
        screen: Bar.GlobalState.rightPanelScreen ? Bar.GlobalState.rightPanelScreen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

        anchors {
            top: true
            right: true
            bottom: true
        }
        implicitWidth: panelWidth

        WlrLayershell.namespace: "quickshell:rightpanel"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0

        Shortcut {
            context: Qt.ApplicationShortcut
            enabled: rightPanelWindow.visible
            sequence: "Escape"
            onActivated: Bar.GlobalState.rightPanelVisible = false
        }

        Item {
            id: rightPanelContainer
            y: Bar.Config.outerGaps
            width: rightPanelWindow.panelWidth
            height: parent.height - Bar.Config.outerGaps * 2

            x: Bar.GlobalState.rightPanelVisible ? 0 : rightPanelWindow.panelWidth

            Behavior on x {
                NumberAnimation {
                    id: rightPanelSlide
                    duration: Bar.Config.motion.duration.medium
                    easing.type: Bar.GlobalState.rightPanelVisible ? Easing.OutCubic : Easing.InCubic
                    onRunningChanged: {
                        if (!running) {
                            shellRoot.rightPanelAnimating = false;
                            if (!Bar.GlobalState.rightPanelVisible) {
                                rightFocusGrab.active = false;
                            }
                        }
                    }
                }
            }

            RightPanel.RightPanel {
                anchors.fill: parent
            }
        }
    }
}
