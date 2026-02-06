import "."
import "./modules"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property int contentHeight: content.implicitHeight + Config.barPadding * 2 + Config.moduleMarginBottom * 2
    property var modelData
    property var targetScreen: modelData

    // A bar should sit above normal clients; Background can end up behind
    // tiled/fullscreen windows depending on compositor behavior.
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors.left: true
    anchors.right: true
    anchors.top: true
    color: "transparent"
    exclusiveZone: implicitHeight
    implicitHeight: Math.max(Config.barHeight, root.contentHeight)
    screen: root.targetScreen

    Rectangle {
        anchors.fill: parent
        color: Config.barBackground
    }
    Item {
        id: content

        anchors.fill: parent
        anchors.margins: Config.barPadding
        implicitHeight: Math.max(leftRow.implicitHeight, centerRow.implicitHeight, rightRow.implicitHeight)

        RowLayout {
            id: leftRow

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Config.moduleSpacing

            StartMenuGroup {}
            WorkspaceGroup {
                screen: root.targetScreen
            }
        }
        RowLayout {
            id: centerRow

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            spacing: Config.moduleSpacing

            MprisModule {}
        }
        RowLayout {
            id: rightRow

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Config.moduleSpacing

            IdleInhibitModule {
                targetWindow: root
            }
            ControlsGroup {}
            WirelessGroup {}
            BatteryModule {}
            ToDoModule {}
            ClockModule {}
            PanelGroup {
                parentWindow: root
            }
        }
    }
}
