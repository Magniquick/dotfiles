import "./config.js" as ScreenshotsConfig
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: pillWindow

    required property var targetScreen
    property var colors: ColorPalette.palette
    property bool hovered: false
    readonly property int padding: 12

    signal requestClose

    screen: targetScreen
    color: "transparent"
    visible: false
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.exclusiveZone: 0
    WlrLayershell.namespace: "screenshots"
    implicitWidth: targetScreen ? targetScreen.geometry.width : implicitWidth
    implicitHeight: targetScreen ? targetScreen.geometry.height : implicitHeight
    onVisibleChanged: {
        if (visible)
            pillContainer.forceActiveFocus();
        else
            hovered = false;
    }
    Component.onCompleted: {
        if (visible)
            pillContainer.forceActiveFocus();
    }

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    Item {
        id: pillContainer

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: padding
        implicitWidth: pill.implicitWidth + padding * 2
        implicitHeight: pill.implicitHeight + padding * 2

        FocusScope {
            anchors.fill: parent
            focus: pillWindow.visible
        }

        Shortcut {
            sequences: ["Escape", "q", "Q"]
            enabled: pillWindow.visible
            context: Qt.ApplicationShortcut
            onActivated: requestClose()
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
        }

        Rectangle {
            id: pill

            anchors.centerIn: parent
            implicitWidth: 260
            implicitHeight: 56
            radius: height / 2
            color: hovered ? colors.surface1 : colors.surface0
            opacity: ScreenshotsConfig.pillOpacity
            border.width: 2
            border.color: hovered ? colors.overlay1 : colors.overlay0
            antialiasing: true
            layer.enabled: true
            layer.smooth: true
            scale: hovered ? 1.04 : 1

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 18
                spacing: 12

                Rectangle {
                    width: 16
                    height: 16
                    radius: width / 2
                    color: colors.sapphire
                    border.width: 2
                    border.color: colors.overlay1
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: "Screenshots pill"
                        color: colors.text
                        font.pixelSize: 16
                        font.bold: true
                        horizontalAlignment: Text.AlignLeft
                        verticalAlignment: Text.AlignVCenter
                    }

                    Text {
                        text: "Floating anchor for captures"
                        color: colors.subtext0
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignLeft
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: pillWindow.hovered = true
                onExited: pillWindow.hovered = false
                onClicked: pillWindow.requestClose()
            }

            Behavior on color {
                ColorAnimation {
                    duration: 120
                    easing.type: Easing.OutQuad
                }
            }

            Behavior on border.color {
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
        }
    }

    mask: Region {
        item: pill
    }
}
