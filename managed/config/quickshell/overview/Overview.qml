pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../common" as Common

Scope {
    id: root

    readonly property var hyprland: Hyprland
    readonly property var targetMonitor: overviewWindow.screen ? hyprland.monitorFor(overviewWindow.screen) : null
    readonly property var targetMonitorIpc: targetMonitor && targetMonitor.lastIpcObject ? targetMonitor.lastIpcObject : null
    readonly property var reservedEdges: targetMonitorIpc && targetMonitorIpc.reserved ? targetMonitorIpc.reserved : [0, 0, 0, 0]
    readonly property real reservedLeft: reservedEdges.length > 0 ? Number(reservedEdges[0]) || 0 : 0
    readonly property real reservedTop: reservedEdges.length > 1 ? Number(reservedEdges[1]) || 0 : 0
    readonly property real reservedRight: reservedEdges.length > 2 ? Number(reservedEdges[2]) || 0 : 0
    readonly property real reservedBottom: reservedEdges.length > 3 ? Number(reservedEdges[3]) || 0 : 0
    readonly property real workAreaWidth: Math.max(0, overviewWindow.width - reservedLeft - reservedRight)
    readonly property real workAreaHeight: Math.max(0, overviewWindow.height - reservedTop - reservedBottom)

    function focusedScreen() {
        const focusedMonitor = hyprland.focusedMonitor;
        if (focusedMonitor) {
            for (let i = 0; i < Quickshell.screens.length; ++i) {
                const screen = Quickshell.screens[i];
                const monitor = hyprland.monitorFor(screen);
                if (monitor && monitor.id === focusedMonitor.id)
                    return screen;
            }
        }

        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    function openForFocusedScreen() {
        hyprland.refreshWorkspaces();
        hyprland.refreshMonitors();
        hyprland.refreshToplevels();
        Common.GlobalState.openOverview(root.focusedScreen());
    }

    IpcHandler {
        target: "overview"

        function toggle() {
            Common.GlobalState.toggleOverview(root.focusedScreen());
        }

        function workspacesToggle() {
            Common.GlobalState.toggleOverview(root.focusedScreen());
        }

        function close() {
            Common.GlobalState.closeOverview();
        }

        function open() {
            root.openForFocusedScreen();
        }
    }

    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggle the workspace overview overlay"
        onPressed: Common.GlobalState.toggleOverview(root.focusedScreen())
    }

    HyprlandFocusGrab {
        id: focusGrab
        active: Common.GlobalState.overviewVisible
        windows: [overviewWindow]
        onCleared: Common.GlobalState.closeOverview()
    }

    PanelWindow {
        id: overviewWindow

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

        color: "transparent"
        exclusiveZone: 0
        screen: Common.GlobalState.overviewScreen ? Common.GlobalState.overviewScreen : root.focusedScreen()
        visible: Common.GlobalState.overviewVisible

        WlrLayershell.namespace: "quickshell:overview"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay

        Shortcut {
            context: Qt.ApplicationShortcut
            enabled: overviewWindow.visible
            sequence: "Escape"
            onActivated: Common.GlobalState.closeOverview()
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Common.Config.color.surface_dim, 0.84)

            MouseArea {
                anchors.fill: parent
                onClicked: Common.GlobalState.closeOverview()
            }

            Item {
                id: dragLayer
                anchors.fill: parent
                z: 3
            }

            Item {
                id: overviewBody
                width: overviewWidget.implicitWidth
                height: overviewWidget.implicitHeight
                x: root.reservedLeft + Math.max(0, (root.workAreaWidth - width) / 2)
                y: root.reservedTop + Math.max(0, (root.workAreaHeight - height) / 2)
                z: 2
                property real bodyScale: Common.GlobalState.overviewVisible ? 1 : 0.97

                transform: Scale {
                    origin.x: overviewBody.width / 2
                    origin.y: overviewBody.height / 2
                    xScale: overviewBody.bodyScale
                    yScale: overviewBody.bodyScale
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Common.Config.motion.duration.shortMs
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on bodyScale {
                    NumberAnimation {
                        duration: Common.Config.motion.duration.shortMs
                        easing.type: Easing.OutCubic
                    }
                }

                opacity: Common.GlobalState.overviewVisible ? 1 : 0

                MouseArea {
                    anchors.fill: parent
                }

                WorkspaceOverviewWidget {
                    id: overviewWidget
                    anchors.fill: parent
                    dragLayer: dragLayer
                    livePreviews: false
                }
            }
        }
    }
}
