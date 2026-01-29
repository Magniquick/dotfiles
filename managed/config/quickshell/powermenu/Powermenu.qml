import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "common" as Common

PanelWindow {
    id: window

    readonly property color borderColor: colors.outline_variant
    readonly property int borderRadius: 27
    property alias bunnyHeadpatting: rightPane.bunnyHeadpatting
    property var colors: Common.Config.color
    property int headpatResetDelay: 200
    property string hoverAction: ""
    property bool hoverEnabled: true
    // Drives the staged button reveal animation.
    property bool revealButtons: false
    property string selection: ""
    property bool suppressNextHover: false
    required property var targetScreen

    signal actionInvoked(string actionName)
    signal hoverUpdated(string actionName)
    signal requestClose

    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "powermenu"
    color: "transparent"
    screen: targetScreen
    visible: false

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
        bottom: true
        left: true
        right: true
        top: true
    }
    // focus handling is done via a global Shortcut in shell.qml

    Rectangle {
        anchors.fill: parent
        color: "transparent"
    }
    MouseArea {
        anchors.fill: parent
        z: 0

        onClicked: window.requestClose()
    }
    Shortcut {
        context: Qt.ApplicationShortcut
        enabled: window.visible
        sequences: ["Escape", "Q", "A"]

        onActivated: window.requestClose()
    }
    Timer {
        id: revealTimer

        interval: 30
        repeat: false

        onTriggered: window.revealButtons = true
    }
    Timer {
        id: hoverEnableTimer

        interval: 450
        repeat: false

        onTriggered: window.hoverEnabled = true
    }
    Item {
        id: content

        anchors.centerIn: parent
        z: 1

        Row {
            id: row

            property real panelHeight: Math.max(leftPane.implicitHeight, rightPane.implicitHeight)
            property real panelWidth: Math.max(leftPane.implicitWidth, rightPane.implicitWidth)

            anchors.centerIn: parent
            spacing: -27

            GreetingPane {
                id: leftPane

                anchors.verticalCenter: parent.verticalCenter
                borderColor: window.borderColor
                borderRadius: window.borderRadius
                colors: window.colors
                headpatting: window.bunnyHeadpatting
                height: row.panelHeight
                width: row.panelWidth
            }
            ActionPanel {
                id: rightPane

                anchors.verticalCenter: parent.verticalCenter
                borderColor: window.borderColor
                borderRadius: window.borderRadius
                colors: window.colors
                headpatResetDelay: window.headpatResetDelay
                height: row.panelHeight
                hoverAction: window.hoverAction
                hoverEnabled: window.hoverEnabled
                reveal: window.revealButtons
                selection: window.selection
                suppressNextHover: window.suppressNextHover
                width: row.panelWidth

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
