import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import "./common" as Common

ShellRoot {
    id: root

    readonly property int panelWidth: 420

    HyprlandFocusGrab {
        id: focusGrab
        active: Common.GlobalState.rightPanelVisible
        windows: panelLoader.item ? [panelLoader.item] : []
        onCleared: Common.GlobalState.rightPanelVisible = false
    }

    Loader {
        id: panelLoader
        active: Common.GlobalState.rightPanelVisible
        sourceComponent: PanelWindow {
            color: "transparent"
            implicitWidth: root.panelWidth

            anchors {
                top: true
                right: true
                bottom: true
            }

            WlrLayershell.namespace: "quickshell:right-panel"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            WlrLayershell.layer: WlrLayer.Top
            exclusiveZone: 0

            RightPanel {
                id: panel
                anchors.fill: parent
                anchors.topMargin: Common.Config.outerGaps
                anchors.bottomMargin: Common.Config.outerGaps
            }
        }
    }
}
