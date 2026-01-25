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
    property bool copyEnabled: false

    signal send(string text)
    signal commandTriggered(string command)
    signal copyAllRequested()

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
                color: Common.Config.color.primary
            }
            GradientStop {
                position: 1.0
                color: Common.Config.color.primary
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
            color: Common.Config.color.surface_container_highest
            radius: Common.Config.shape.corner.lg
            border.width: 1
            border.color: inputField.activeFocus ? Common.Config.color.primary : Common.Config.color.outline

            Behavior on border.color {
                ColorAnimation {
                    duration: 200
                }
            }

            HoverHandler { id: composerHover }

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
                    color: Common.Config.color.on_surface
                    font.family: Common.Config.fontFamily
                    font.pixelSize: Common.Config.type.bodyMedium.size + 1
                    placeholderTextColor: Common.Config.color.on_surface_variant
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
                    id: copyButton
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: Common.Config.space.xs
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    implicitWidth: 36
                    implicitHeight: 36
                    radius: Common.Config.shape.corner.md
                    color: copyArea.containsMouse ? Qt.alpha(Common.Config.color.primary, 0.12) : "transparent"
                    border.width: 1
                    border.color: copyArea.containsMouse ? Qt.alpha(Common.Config.color.outline, 0.6) : "transparent"
                    visible: root.copyEnabled && composerHover.hovered

                    Text {
                        anchors.centerIn: parent
                        text: "\udb80\udd8f"
                        color: copyArea.containsMouse ? Common.Config.color.primary : Common.Config.color.on_surface_variant
                        font.family: Common.Config.iconFontFamily
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: copyArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.copyAllRequested()
                    }

                    ToolTip.visible: copyArea.containsMouse
                    ToolTip.text: "Copy Conversation"
                    ToolTip.delay: 400
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
                    color: root.busy ? Common.Config.color.surface_container_highest : Common.Config.color.primary

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
                            color: root.busy ? Common.Config.color.on_surface_variant : Common.Config.color.on_primary
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
                                    color: Common.Config.color.on_surface_variant

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
