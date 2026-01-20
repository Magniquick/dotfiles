pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../common" as Common

Item {
    id: root
    property bool busy: false
    property string placeholderText: "Type a message..."
    property alias text: inputField.text

    signal send(string text)
    signal commandTriggered(string command)

    implicitHeight: composerContainer.implicitHeight

    function handleSend() {
        const text = inputField.text.trim();
        if (text.length === 0)
            return;

        if (text.startsWith("/")) {
            root.commandTriggered(text);
        } else {
            root.send(text);
        }
    }

    component GlowLayer: Rectangle {
        property real marginSize: 2
        property real focusedOpacity: 0.3
        property real unfocusedOpacity: 0.1

        anchors.fill: inputContainer
        anchors.margins: -marginSize
        radius: Common.Config.shape.corner.lg + marginSize
        opacity: inputField.activeFocus ? focusedOpacity : unfocusedOpacity
        visible: !root.busy

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: Common.Config.primary
            }
            GradientStop {
                position: 1.0
                color: Common.Config.m3.info
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }
        }
    }

    Item {
        id: composerContainer
        anchors.fill: parent
        implicitHeight: inputContainer.height

        GlowLayer {
            marginSize: 2
            focusedOpacity: 0.3
            unfocusedOpacity: 0.1
        }
        GlowLayer {
            marginSize: 4
            focusedOpacity: 0.15
            unfocusedOpacity: 0
        }

        Rectangle {
            id: inputContainer
            anchors.fill: parent
            color: Common.Config.surface
            radius: Common.Config.shape.corner.lg
            border.width: 1
            border.color: inputField.activeFocus ? Common.Config.primary : Common.Config.outline

            Behavior on border.color {
                ColorAnimation {
                    duration: 200
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: Common.Config.space.sm
                spacing: Common.Config.space.sm

                TextArea {
                    id: inputField
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 48
                    placeholderText: root.placeholderText
                    wrapMode: TextArea.Wrap
                    color: Common.Config.textColor
                    font.family: Common.Config.fontFamily
                    font.pixelSize: Common.Config.type.bodyMedium.size + 1
                    placeholderTextColor: Common.Config.textMuted
                    enabled: !root.busy
                    verticalAlignment: TextArea.AlignVCenter

                    background: Rectangle {
                        color: "transparent"
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return && !(event.modifiers & Qt.ShiftModifier)) {
                            root.handleSend();
                            event.accepted = true;
                        }
                    }
                }

                Rectangle {
                    id: sendButton
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: Common.Config.space.xs
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    implicitWidth: 44
                    implicitHeight: 44
                    radius: Common.Config.shape.corner.md
                    color: root.busy ? Common.Config.surfaceContainerHighest : Common.Config.primary

                    scale: sendButtonArea.pressed ? 0.92 : (sendButtonArea.containsMouse ? 1.05 : 1.0)

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 100
                            easing.type: Easing.OutCubic
                        }
                    }

                    Item {
                        anchors.centerIn: parent

                        Text {
                            anchors.centerIn: parent
                            text: "\uf1d9"
                            color: root.busy ? Common.Config.textMuted : Common.Config.onPrimary
                            font.family: Common.Config.iconFontFamily
                            font.pixelSize: 20
                            visible: !root.busy
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 3
                            visible: root.busy

                            Repeater {
                                model: 3
                                Rectangle {
                                    id: busyDot
                                    required property int index
                                    width: 5
                                    height: 5
                                    radius: 2.5
                                    color: Common.Config.textMuted

                                    SequentialAnimation on opacity {
                                        running: root.busy
                                        loops: Animation.Infinite
                                        PauseAnimation {
                                            duration: busyDot.index * 120
                                        }
                                        NumberAnimation {
                                            to: 0.3
                                            duration: 250
                                        }
                                        NumberAnimation {
                                            to: 1.0
                                            duration: 250
                                        }
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: sendButtonArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        enabled: !root.busy
                        onClicked: root.handleSend()
                    }
                }
            }
        }
    }
}
