import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: window

    property var colors: ColorPalette.palette
    required property var targetScreen
    property string selection: ""
    property string hoverAction: ""
    property bool hoverEnabled: true
    property bool suppressNextHover: false
    property alias bunnyHeadpatting: rightPane.bunnyHeadpatting
    property int headpatResetDelay: 200
    // Drives the staged button reveal animation.
    property bool revealButtons: false
    readonly property color borderColor: Qt.rgba(88 / 255, 91 / 255, 112 / 255, 0.5)
    readonly property int borderRadius: 27

    signal requestClose
    signal actionInvoked(string actionName)
    signal hoverUpdated(string actionName)

    screen: targetScreen
    color: "transparent"
    visible: false
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.namespace: "powermenu"
    onVisibleChanged: {
        if (visible) {
            hoverEnabled = false;
            suppressNextHover = true;
            revealButtons = false;
            revealTimer.restart();
            hoverEnableTimer.restart();
        } else {
            hoverEnabled = true;
            suppressNextHover = false;
            revealButtons = false;
            revealTimer.stop();
            hoverEnableTimer.stop();
        }
    }

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }
    // focus handling is done via a global Shortcut in shell.qml

    Rectangle {
        anchors.fill: parent
        color: "transparent"
    }

    MouseArea {
        anchors.fill: parent
        z: 0
        onClicked: requestClose()
    }

    Shortcut {
        sequences: ["Escape", "Q", "A"]
        enabled: window.visible
        context: Qt.ApplicationShortcut
        onActivated: requestClose()
    }

    Timer {
        id: revealTimer

        interval: 30
        repeat: false
        onTriggered: revealButtons = true
    }

    Timer {
        id: hoverEnableTimer

        interval: 450
        repeat: false
        onTriggered: hoverEnabled = true
    }

    Item {
        id: content

        z: 1
        anchors.centerIn: parent

        Row {
            id: row

            property real panelWidth: Math.max(leftPane.implicitWidth, rightPane.implicitWidth)
            property real panelHeight: Math.max(leftPane.implicitHeight, rightPane.implicitHeight)

            anchors.centerIn: parent
            spacing: -27

            GreetingPane {
                id: leftPane

                colors: window.colors
                borderColor: window.borderColor
                borderRadius: window.borderRadius
                headpatting: window.bunnyHeadpatting
                width: row.panelWidth
                height: row.panelHeight
                anchors.verticalCenter: parent.verticalCenter
            }

            ActionPanel {
                id: rightPane

                colors: window.colors
                borderColor: window.borderColor
                borderRadius: window.borderRadius
                headpatResetDelay: window.headpatResetDelay
                selection: window.selection
                hoverAction: window.hoverAction
                hoverEnabled: window.hoverEnabled
                suppressNextHover: window.suppressNextHover
                reveal: window.revealButtons
                width: row.panelWidth
                height: row.panelHeight
                anchors.verticalCenter: parent.verticalCenter
                onActionInvoked: actionName => {
                    return window.actionInvoked(actionName);
                }
                onHoverUpdated: actionName => {
                    return window.hoverUpdated(actionName);
                }
            }
        }
    }
}
