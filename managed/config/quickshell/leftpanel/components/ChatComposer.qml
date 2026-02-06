pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../common" as Common

Item {
    id: root
    property bool busy: false
    property string placeholderText: "Type a message..."
    property alias text: inputEdit.text
    readonly property int maxLines: 5
    readonly property int maxInputHeight: Math.ceil(inputMetrics.lineSpacing * root.maxLines) + inputEdit.topPadding + inputEdit.bottomPadding

    signal send(string text)
    signal commandTriggered(string command)

    implicitHeight: composerContainer.implicitHeight

    function clearFocus() {
        inputEdit.focus = false;
    }

    function handleSend() {
        const text = inputEdit.text.trim();
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
        opacity: inputEdit.activeFocus ? focusedOpacity : unfocusedOpacity
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
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
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
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            implicitHeight: inputRow.implicitHeight + Common.Config.space.sm * 2
            height: implicitHeight
            color: Common.Config.color.surface_container_highest
            radius: Common.Config.shape.corner.lg
            border.width: 1
            border.color: inputEdit.activeFocus ? Common.Config.color.primary : Common.Config.color.outline

            Behavior on border.color {
                ColorAnimation {
                    duration: 200
                }
            }

            HoverHandler { id: composerHover }
            TapHandler {
                id: composerTap
                onTapped: inputEdit.forceActiveFocus()
            }

            RowLayout {
                id: inputRow
                anchors.fill: parent
                anchors.margins: Common.Config.space.sm
                spacing: Common.Config.space.sm

                Item {
                    id: inputWrap
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(48, Math.min(textFlick.contentHeight, root.maxInputHeight))

                    function scrollToThumbY(localY) {
                        const maxThumbY = Math.max(0, inputWrap.height - scrollThumb.height);
                        const clampedY = Math.max(0, Math.min(maxThumbY, localY - scrollThumb.height / 2));
                        const range = Math.max(1, textFlick.contentHeight - inputWrap.height);
                        textFlick.contentY = maxThumbY > 0 ? (clampedY / maxThumbY) * range : 0;
                    }

                    Flickable {
                        id: textFlick
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: inputEdit.height
                        clip: true

                        TextEdit {
                            id: inputEdit
                            width: textFlick.width
                            height: contentHeight + topPadding + bottomPadding
                            y: Math.max(0, (inputWrap.height - height) / 2)
                            text: ""
                            wrapMode: TextEdit.Wrap
                            color: Common.Config.color.on_surface
                            font.family: Common.Config.fontFamily
                            font.pixelSize: Common.Config.type.bodyMedium.size + 1
                            selectionColor: Common.Config.color.primary
                            selectedTextColor: Common.Config.color.on_primary
                            readOnly: root.busy
                            cursorVisible: inputEdit.activeFocus && !root.busy
                            focus: false
                            activeFocusOnPress: true
                            topPadding: 4
                            bottomPadding: 4
                            leftPadding: 0
                            rightPadding: 8
                            onActiveFocusChanged: {
                                if (!activeFocus) {
                                    inputEdit.cursorPosition = inputEdit.text.length;
                                }
                            }

                            onTextChanged: {
                                // keep the flickable height in sync
                                textFlick.contentHeight = inputEdit.y + inputEdit.height;
                                if (textFlick.contentHeight > textFlick.height) {
                                    textFlick.contentY = textFlick.contentHeight - textFlick.height;
                                } else {
                                    textFlick.contentY = 0;
                                }
                            }

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Return && !(event.modifiers & Qt.ShiftModifier)) {
                                    root.handleSend();
                                    event.accepted = true;
                                }
                            }
                        }

                        ScrollBar.vertical: null
                    }

                    Rectangle {
                        id: scrollTrack
                        anchors.right: parent.right
                        anchors.rightMargin: 0
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 6
                        color: "transparent"
                        visible: scrollThumb.visible
                        z: 2

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: event => inputWrap.scrollToThumbY(event.y)
                            onPositionChanged: event => {
                                if (pressed)
                                    inputWrap.scrollToThumbY(event.y);
                            }
                        }
                    }

                    Rectangle {
                        id: scrollThumb
                        anchors.right: parent.right
                        anchors.rightMargin: 1
                        width: 4
                        height: Math.max(12, inputWrap.height * (inputWrap.height / Math.max(1, textFlick.contentHeight)))
                        y: Math.min(inputWrap.height - height, textFlick.contentY / Math.max(1, textFlick.contentHeight - inputWrap.height) * (inputWrap.height - height))
                        radius: 2
                        color: Common.Config.color.on_surface_variant
                        visible: textFlick.contentHeight > inputWrap.height + 1
                        z: 3
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        color: Common.Config.color.on_surface_variant
                        font.family: Common.Config.fontFamily
                        font.pixelSize: Common.Config.type.bodyMedium.size + 1
                        text: root.placeholderText
                        visible: inputEdit.text.length === 0
                        opacity: 0.8
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
                                        running: root.busy && root.visible && root.QsWindow.window && root.QsWindow.window.visible
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

    FontMetrics {
        id: inputMetrics

        font.family: Common.Config.fontFamily
        font.pixelSize: Common.Config.type.bodyMedium.size + 1
    }
}
