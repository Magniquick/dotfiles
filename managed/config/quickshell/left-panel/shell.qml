import Quickshell
import Quickshell.Wayland
import QtQuick
ShellRoot {
    id: root

    readonly property int panelWidth: 380

    PanelWindow {
        id: panelWindow
        color: "transparent"
        visible: true
        implicitWidth: panelWidth

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
        }
    }
}
