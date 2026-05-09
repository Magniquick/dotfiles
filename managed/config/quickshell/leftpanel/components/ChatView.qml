pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Templates as T
import "../../common/materialkit" as MK
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

    signal sendRequested(string text, var attachments)
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

    function setLatestVisibleToolExpanded(expanded) {
        messageList.positionViewAtEnd();
        messageList.forceLayout();
        for (let i = messageList.count - 1; i >= 0; --i) {
            const item = messageList.itemAtIndex(i);
            if (!item || item.kind !== "tool")
                continue;
            messageList.setToolRowExpanded(item._messageId, item.tool, expanded);
            return true;
        }
        return false;
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

        MK.Pane {
            anchors.fill: parent
            backgroundColor: Common.Config.color.surface_container_low
            radius: Common.Config.shape.corner.md
        }

        MK.ListView {
            id: messageList
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10
            clip: true
            model: root.messagesModel
            property string activeSelectionKey: ""
            property var toolExpansionState: ({})

            // Follow output as it streams, but don't fight the user if they've scrolled up.
            property bool autoFollow: true

            function toolRowKey(messageId, tool) {
                const id = String(messageId || "");
                if (id.length > 0)
                    return id;
                return String((tool || ({})).tool_call_id || "");
            }

            function toolRowExpanded(messageId, tool) {
                const key = toolRowKey(messageId, tool);
                return key.length > 0 && !!toolExpansionState[key];
            }

            function withToolExpansionValue(state, key, value) {
                const next = {};
                for (const existingKey in state)
                    next[existingKey] = state[existingKey];
                if (value)
                    next[key] = true;
                else
                    delete next[key];
                return next;
            }

            function setToolRowExpanded(messageId, tool, expanded) {
                const key = toolRowKey(messageId, tool);
                if (key.length === 0)
                    return;
                toolExpansionState = withToolExpansionValue(toolExpansionState, key, expanded);
            }

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

            T.ScrollBar.vertical: MK.ScrollBar {
                policy: T.ScrollBar.AsNeeded
                width: 4
                background: Rectangle { color: "transparent" }
                contentItem: Rectangle {
                    implicitWidth: 4
                    radius: 2
                    color: Qt.alpha(Common.Config.color.primary, 0.3)
                }
            }

            delegate: Item {
                id: delegateRoot
                required property int index
                required property string messageId
                required property string sender
                required property string body
                required property string kind
                required property var metrics
                required property var attachments
                required property var tool
                required property bool showHeader

                width: messageList.width
                implicitHeight: contentLoader.item ? contentLoader.item.implicitHeight : 0
                property string _messageId: messageId
                property bool emptyAssistantPlaceholder: kind !== "tool"
                    && sender === "assistant"
                    && String(body || "").trim().length === 0
                    && !(root.busy && index === (messageList.count - 1))

                Loader {
                    id: contentLoader
                    width: parent.width
                    sourceComponent: delegateRoot.emptyAssistantPlaceholder
                        ? null
                        : (delegateRoot.kind === "tool" ? toolRowComponent : chatMessageComponent)
                }

                Component {
                    id: chatMessageComponent

                    Components.ChatMessage {
                        width: delegateRoot.width
                        messageIndex: delegateRoot.index
                        role: delegateRoot.sender
                        content: delegateRoot.body
                        metrics: delegateRoot.metrics
                        attachments: delegateRoot.attachments
                        activeSelectionKey: messageList.activeSelectionKey
                        modelLabel: delegateRoot.sender === "assistant" ? root.modelLabel : ""
                        moodIcon: root.moodIcon
                        moodName: root.moodName
                        showHeader: delegateRoot.showHeader
                        // The backend inserts an assistant message up-front and streams into it.
                        // Treat the last assistant message as "streaming" while busy, and render a
                        // lightweight view to avoid expensive markdown/code-block reflows per chunk.
                        streaming: root.busy
                            && delegateRoot.sender === "assistant"
                            && delegateRoot.index === (messageList.count - 1)
                        thinking: streaming && String(delegateRoot.body || "").trim().length === 0
                        done: !streaming

                        onRegenerateRequested: root.regenerateRequested(delegateRoot._messageId)
                        onDeleteRequested: root.deleteRequested(delegateRoot._messageId)
                        onEditSaved: newContent => root.editRequested(delegateRoot._messageId, newContent)
                        onSelectionActivated: selectionKey => messageList.activeSelectionKey = selectionKey
                    }
                }

                Component {
                    id: toolRowComponent

                    Components.ToolCallRow {
                        width: delegateRoot.width
                        tool: delegateRoot.tool
                        expanded: messageList.toolRowExpanded(delegateRoot._messageId, delegateRoot.tool)
                        moodIcon: root.moodIcon
                        moodName: root.moodName
                        onExpandedChangeRequested: expanded => messageList.setToolRowExpanded(delegateRoot._messageId, delegateRoot.tool, expanded)
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
            chatSession: root.chatSession
            placeholderText: root.connectionOnline ? "Message..." : "Offline - use /model to switch"
            onSend: function(text, attachments) {
                // When we send a message, re-enable following the tail.
                messageList.autoFollow = true;
                root.sendRequested(text, attachments);
            }
            onCommandTriggered: command => {
                messageList.autoFollow = true;
                root.commandTriggered(command);
            }
        }
    }
}
