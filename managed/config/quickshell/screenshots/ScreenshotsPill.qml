import "./config.js" as ScreenshotsConfig
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: pillWindow

    property var colors: ColorPalette.palette
    property bool hovered: false
    readonly property int padding: 12
    required property var targetScreen

    signal requestClose

    WlrLayershell.exclusiveZone: 0
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "screenshots"
    color: "transparent"
    implicitHeight: targetScreen ? targetScreen.geometry.height : implicitHeight
    implicitWidth: targetScreen ? targetScreen.geometry.width : implicitWidth
    screen: targetScreen
    visible: false

    mask: Region {
        item: pill
    }

    Component.onCompleted: {
        if (visible)
            pillContainer.forceActiveFocus();
    }
    onVisibleChanged: {
        if (visible)
            pillContainer.forceActiveFocus();
        else
            hovered = false;
    }

    anchors {
        bottom: true
        left: true
        right: true
        top: true
    }
    Item {
        id: pillContainer

        anchors.bottom: parent.bottom
        anchors.bottomMargin: padding
        anchors.horizontalCenter: parent.horizontalCenter
        implicitHeight: pill.implicitHeight + padding * 2
        implicitWidth: pill.implicitWidth + padding * 2

        FocusScope {
            anchors.fill: parent
            focus: pillWindow.visible
        }
        Shortcut {
            context: Qt.ApplicationShortcut
            enabled: pillWindow.visible
            sequences: ["Escape", "q", "Q"]

            onActivated: requestClose()
        }
        Rectangle {
            anchors.fill: parent
            color: "transparent"
        }
        Rectangle {
            id: pill

            anchors.centerIn: parent
            antialiasing: true
            border.color: hovered ? colors.overlay1 : colors.overlay0
            border.width: 2
            color: hovered ? colors.surface1 : colors.surface0
            implicitHeight: 56
            implicitWidth: 260
            layer.enabled: true
            layer.smooth: true
            opacity: ScreenshotsConfig.pillOpacity
            radius: height / 2
            scale: hovered ? 1.04 : 1

            Behavior on border.color {
                ColorAnimation {
                    duration: 120
                    easing.type: Easing.OutQuad
                }
            }
            Behavior on color {
                ColorAnimation {
                    duration: 120
                    easing.type: Easing.OutQuad
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }

            Row {
                anchors.left: parent.left
                anchors.margins: 18
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    border.color: colors.overlay1
                    border.width: 2
                    color: colors.sapphire
                    height: 16
                    radius: width / 2
                    width: 16
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        color: colors.text
                        font.bold: true
                        font.pixelSize: 16
                        horizontalAlignment: Text.AlignLeft
                        text: "Screenshots pill"
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        color: colors.subtext0
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignLeft
                        text: "Floating anchor for captures"
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true

                onClicked: pillWindow.requestClose()
                onEntered: pillWindow.hovered = true
                onExited: pillWindow.hovered = false
            }
        }
    }
}
