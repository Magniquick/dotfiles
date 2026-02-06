import Quickshell
import Quickshell.Wayland
import QtQuick
import "../common" as Common

ShellRoot {
    id: root

    readonly property int panelWidth: 380
    readonly property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    PanelWindow {
        id: panelWindow
        color: "transparent"
        visible: true
        implicitWidth: root.panelWidth
        screen: root.targetScreen

        anchors {
            top: true
            left: true
            bottom: true
        }

        WlrLayershell.namespace: "quickshell:left-panel"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Top
        exclusiveZone: 0

        LeftPanel {
            id: panel
            anchors.fill: parent
            anchors.topMargin: Common.Config.outerGaps
            anchors.bottomMargin: Common.Config.outerGaps
        }
    }
}
