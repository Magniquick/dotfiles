pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../common" as Common

Item {
    id: root
    property int messageIndex: -1
    property string role: "assistant"
    property string content: ""
    property string modelLabel: ""
    property string moodIcon: "\uf4c4"
    property string moodName: "Assistant"
    property bool done: true

    property bool editing: false
    property bool renderMarkdown: true

    signal regenerateRequested()
    signal deleteRequested()
    signal editSaved(string newContent)

    readonly property bool isAssistant: role === "assistant"
    readonly property bool isUser: role === "user"
    readonly property color accentColor: isUser ? Common.Config.color.primary : Common.Config.color.primary

    // Parse content into blocks (text and code)
    readonly property var contentBlocks: {
        const blocks = [];
        const text = content;
        const codeBlockRegex = /```(\w*)\n([\s\S]*?)```/g;
        let lastIndex = 0;
        let match;

        while ((match = codeBlockRegex.exec(text)) !== null) {
            if (match.index > lastIndex) {
                const textBefore = text.substring(lastIndex, match.index).trim();
                if (textBefore) blocks.push({ type: "text", content: textBefore });
            }
            blocks.push({
                type: "code",
                language: match[1] || "txt",
                content: match[2].replace(/\n$/, "")
            });
            lastIndex = match.index + match[0].length;
        }

        if (lastIndex < text.length) {
            const remaining = text.substring(lastIndex).trim();
            if (remaining) blocks.push({ type: "text", content: remaining });
        }

        if (blocks.length === 0 && text.trim()) {
            blocks.push({ type: "text", content: text });
        }

        return blocks;
    }

    implicitHeight: mainRow.implicitHeight + separator.height + 16
    implicitWidth: parent ? parent.width : 300

    RowLayout {
        id: mainRow
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        spacing: 0

        // Content column
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            // Header row with label and actions
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    radius: 7
                    color: Qt.alpha(Common.Config.color.on_surface, 0.05)

                    Text {
                        anchors.centerIn: parent
                        text: root.isAssistant ? root.moodIcon : "\uf4ff"
                        color: root.accentColor
                        font.family: Common.Config.iconFontFamily
                        font.pixelSize: 14
                    }
                }

                // Role label (uppercase like metrics)
                Text {
                    text: root.isAssistant ? (root.moodName || "ASSISTANT") : "YOU"
                    color: Common.Config.color.on_surface_variant
                    font {
                        family: Common.Config.fontFamily
                        pixelSize: 11
                        weight: Font.Bold
                        letterSpacing: 1.5
                        capitalization: Font.AllUppercase
                    }
                    opacity: 0.5
                }

                Item { Layout.fillWidth: true }

                // Action buttons (appear on hover)
                Row {
                    spacing: 2
                    opacity: messageHover.hovered ? 1 : 0
                    enabled: messageHover.hovered

                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }

                    MessageControlButton {
                        visible: root.isAssistant && root.done
                        icon: "\udb81\udc50"
                        onClicked: root.regenerateRequested()
                        ToolTip.visible: hovered; ToolTip.text: "Regenerate"; ToolTip.delay: 400
                        property bool hovered: h1.hovered; HoverHandler { id: h1 }
                    }

                    MessageControlButton {
                        id: copyBtn
                        property bool copied: false
                        icon: copied ? "\udb80\udd91" : "\uf0c5"
                        activated: copied
                        onClicked: { Quickshell.clipboardText = root.content; copied = true; copyTimer.restart() }
                        Timer { id: copyTimer; interval: 1500; onTriggered: copyBtn.copied = false }
                        ToolTip.visible: hovered; ToolTip.text: copied ? "Copied!" : "Copy"; ToolTip.delay: 400
                        property bool hovered: h2.hovered; HoverHandler { id: h2 }
                    }

                    MessageControlButton {
                        visible: root.done
                        icon: "\uf044"
                        activated: root.editing
                        onClicked: {
                            if (root.editing) { root.editSaved(fullEditArea.text); root.editing = false }
                            else { root.editing = true; fullEditArea.text = root.content }
                        }
                        ToolTip.visible: hovered; ToolTip.text: root.editing ? "Save" : "Edit"; ToolTip.delay: 400
                        property bool hovered: h3.hovered; HoverHandler { id: h3 }
                    }

                    MessageControlButton {
                        icon: "\uf121"
                        activated: !root.renderMarkdown
                        onClicked: root.renderMarkdown = !root.renderMarkdown
                        ToolTip.visible: hovered; ToolTip.text: root.renderMarkdown ? "Source" : "Render"; ToolTip.delay: 400
                        property bool hovered: h4.hovered; HoverHandler { id: h4 }
                    }

                    MessageControlButton {
                        icon: "\uf00d"
                        onClicked: root.deleteRequested()
                        ToolTip.visible: hovered; ToolTip.text: "Delete"; ToolTip.delay: 400
                        property bool hovered: h5.hovered; HoverHandler { id: h5 }
                    }
                }
            }

            // Content blocks
            Repeater {
                model: (root.editing || !root.renderMarkdown) ? [] : root.contentBlocks

                Loader {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.topMargin: index === 0 ? 0 : 1

                    sourceComponent: modelData.type === "code" ? codeBlockComponent : textBlockComponent

                    Component {
                        id: codeBlockComponent
                        MessageCodeBlock {
                            code: modelData.content
                            language: modelData.language
                            editing: false
                        }
                    }

                    Component {
                        id: textBlockComponent
                        TextEdit {
                            text: modelData.content
                            textFormat: root.renderMarkdown ? TextEdit.MarkdownText : TextEdit.PlainText
                            color: Common.Config.color.on_surface
                            wrapMode: TextEdit.Wrap
                            font.family: Common.Config.fontFamily
                            font.pixelSize: 13
                            readOnly: true
                            selectByMouse: true
                            cursorVisible: false
                            activeFocusOnPress: false

                            onLinkActivated: link => Qt.openUrlExternally(link)

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.NoButton
                                hoverEnabled: true
                                cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor
                            }
                        }
                    }
                }
            }

            // Raw markdown/source view
            TextEdit {
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: !root.editing && !root.renderMarkdown
                text: root.content
                textFormat: TextEdit.PlainText
                color: Common.Config.color.on_surface
                wrapMode: TextEdit.Wrap
                font.family: "JetBrainsMono NFP"
                font.pixelSize: 12
                readOnly: true
                selectByMouse: true
                cursorVisible: false
                activeFocusOnPress: false
            }

            // Edit area
            TextArea {
                id: fullEditArea
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: root.editing
                text: root.content
                color: Common.Config.color.on_surface
                wrapMode: TextEdit.Wrap
                font.family: Common.Config.fontFamily
                font.pixelSize: 13
                padding: Common.Config.space.sm
                background: Rectangle {
                    color: Qt.alpha(Common.Config.color.on_surface, 0.03)
                    radius: Common.Config.shape.corner.sm
                    border.width: 1
                    border.color: Common.Config.color.primary
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_S && event.modifiers === Qt.ControlModifier) {
                        root.editSaved(fullEditArea.text); root.editing = false; event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                        root.editing = false; event.accepted = true
                    }
                }
            }
        }
    }

    // Separator line (like metrics sections)
    Rectangle {
        id: separator
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 1
        color: Qt.alpha(Common.Config.color.on_surface, 0.05)
    }

    HoverHandler { id: messageHover }
}
