pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../common" as Common
import "./" as Components

Item {
    id: root
    property var messagesModel
    property var chatSession: null
    property bool busy: false
    property string modelId: ""
    property string modelLabel: ""
    property bool connectionOnline: true
    property string moodIcon: "\uf4c4"
    property string moodName: "Assistant"

    signal sendRequested(string text, string attachmentsJson)
    signal commandTriggered(string command)
    signal regenerateRequested(string messageId)
    signal deleteRequested(string messageId)
    signal editRequested(string messageId, string newContent)

    function positionToEnd() {
        messageList.positionViewAtEnd();
    }

    function copyAllMessages() {
        if (root.chatSession && root.chatSession.copyAllText) {
            Quickshell.clipboardText = root.chatSession.copyAllText();
            return;
        }
    }

    function focusComposer() {
        if (composer && composer.focusInput)
            composer.focusInput();
    }

    function clearTextFocus() {
        if (composer && composer.clearFocus)
            composer.clearFocus();
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
            model: root.messagesModel

            // Follow output as it streams, but don't fight the user if they've scrolled up.
            property bool autoFollow: true

            function maybeFollow() {
                if (!autoFollow)
                    return;
                Qt.callLater(() => messageList.positionViewAtEnd());
            }

            onMovementStarted: {
                // If the user scrolls away from the bottom, stop auto-follow.
                autoFollow = atYEnd;
            }
            onMovementEnded: {
                autoFollow = atYEnd;
            }
            onContentHeightChanged: maybeFollow()

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
                required property string messageId
                required property string sender
                required property string body

                width: messageList.width
                messageIndex: index
                // Expose stable ID for actions.
                property string _messageId: messageId
                role: sender
                content: body
                modelLabel: sender === "assistant" ? root.modelLabel : ""
                moodIcon: root.moodIcon
                moodName: root.moodName
                // The backend inserts an assistant message up-front and streams into it.
                // Treat the last assistant message as "streaming" while busy, and render a
                // lightweight view to avoid expensive markdown/code-block reflows per chunk.
                streaming: root.busy
                    && sender === "assistant"
                    && index === (messageList.count - 1)
                thinking: streaming && String(body || "").trim().length === 0
                done: !streaming

                onRegenerateRequested: root.regenerateRequested(_messageId)
                onDeleteRequested: root.deleteRequested(_messageId)
                onEditSaved: newContent => root.editRequested(_messageId, newContent)
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
            chatSession: root.chatSession
            placeholderText: root.connectionOnline ? "Message..." : "Offline - use /model to switch"
            onSend: function(text, attachmentsJson) {
                // When we send a message, re-enable following the tail.
                messageList.autoFollow = true;
                root.sendRequested(text, attachmentsJson);
            }
            onCommandTriggered: command => {
                messageList.autoFollow = true;
                root.commandTriggered(command);
            }
        }
    }
}
