pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../common" as Common
import "./" as Components

Item {
    id: root
    property ListModel messages
    property bool busy: false
    property string modelId: ""
    property string modelLabel: ""
    property bool connectionOnline: true
    property string moodIcon: "\uf4c4"
    property string moodName: "Assistant"

    signal sendRequested(string text)
    signal commandTriggered(string command)
    signal regenerateRequested(int index)
    signal deleteRequested(int index)
    signal editRequested(int index, string newContent)

    function positionToEnd() {
        messageList.positionViewAtEnd();
    }

    function copyAllMessages() {
        const lines = [];
        for (let i = 0; i < messages.count; i++) {
            const msg = messages.get(i);
            if (msg.body.includes("Chat history cleared") || msg.body.startsWith("Mood:"))
                continue;
            const name = msg.sender === "user" ? "user" : root.moodName.toLowerCase();
            lines.push(`*${name}*: ${msg.body}`);
        }
        Quickshell.clipboardText = lines.join("\n");
    }

    Item {
        id: chatArea
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: composerArea.top

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            propagateComposedEvents: true
            onPressed: mouse => {
                composer.clearFocus();
                mouse.accepted = false;
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Common.Config.color.surface_container_low
            radius: Common.Config.shape.corner.md
        }

        ListView {
            id: messageList
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10
            clip: true
            model: root.messages

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                width: 4
                background: Rectangle { color: "transparent" }
                contentItem: Rectangle {
                    implicitWidth: 4
                    radius: 2
                    color: Qt.alpha(Common.Config.color.primary, 0.3)
                }
            }

            delegate: Components.ChatMessage {
                required property int index
                required property string sender
                required property string body

                width: messageList.width
                messageIndex: index
                role: sender
                content: body
                modelLabel: sender === "assistant" ? root.modelLabel : ""
                moodIcon: root.moodIcon
                moodName: root.moodName
                done: true

                onRegenerateRequested: root.regenerateRequested(index)
                onDeleteRequested: root.deleteRequested(index)
                onEditSaved: newContent => root.editRequested(index, newContent)
            }

            footer: Item {
                width: messageList.width
                height: root.busy ? 48 : 0
                visible: root.busy

                RowLayout {
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: Common.Config.space.sm

                    // Icon box (matches message style)
                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: Common.Config.shape.corner.sm
                        color: Qt.alpha(Common.Config.color.on_surface, 0.05)

                        Text {
                            anchors.centerIn: parent
                            text: root.moodIcon
                            color: Common.Config.color.primary
                            font.family: Common.Config.iconFontFamily
                            font.pixelSize: 14

                            SequentialAnimation on opacity {
                                running: root.busy && root.visible && root.QsWindow.window && root.QsWindow.window.visible
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.4; duration: 600 }
                                NumberAnimation { to: 1.0; duration: 600 }
                            }
                        }
                    }

                    // Typing indicator
                    ColumnLayout {
                        spacing: 2

                        Text {
                            text: "THINKING"
                            color: Common.Config.color.on_surface_variant
                            font {
                                family: Common.Config.fontFamily
                                pixelSize: 9
                                weight: Font.Bold
                                letterSpacing: 1.5
                            }
                            opacity: 0.5
                        }

                        Row {
                            spacing: 4

                            Repeater {
                                model: 3
                                Rectangle {
                                    id: typingDot
                                    required property int index
                                    width: 4
                                    height: 4
                                    radius: 2
                                    color: Common.Config.color.primary

                                    SequentialAnimation on opacity {
                                        running: root.busy && root.visible && root.QsWindow.window && root.QsWindow.window.visible
                                        loops: Animation.Infinite
                                        PauseAnimation { duration: typingDot.index * 200 }
                                        NumberAnimation { to: 0.2; duration: 400 }
                                        NumberAnimation { to: 1.0; duration: 400 }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Item {
        id: composerArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: composer.implicitHeight + Common.Config.space.md * 2

        Components.ChatComposer {
            id: composer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 0
            anchors.rightMargin: 0
            anchors.topMargin: Common.Config.space.md
            anchors.bottomMargin: Common.Config.space.md
            height: implicitHeight
            busy: root.busy
            placeholderText: root.connectionOnline ? "Message..." : "Offline - use /model to switch"
            onSend: text => {
                root.sendRequested(text);
                composer.text = "";
            }
            onCommandTriggered: command => {
                root.commandTriggered(command);
                composer.text = "";
            }
        }
    }
}
