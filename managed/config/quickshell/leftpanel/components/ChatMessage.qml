pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Qcm.Material as MD
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
    property bool thinking: false
    property bool streaming: false

    property bool editing: false
    property bool renderMarkdown: true
    property string metrics: ""
    property string attachments: ""

    property var attachmentList: {
        try { return JSON.parse(root.attachments) } catch(e) { return [] }
    }

    signal regenerateRequested()
    signal deleteRequested()
    signal editSaved(string newContent)

    readonly property bool isAssistant: role === "assistant"
    readonly property bool isUser: role === "user"
    readonly property color accentColor: isUser ? Common.Config.color.primary : Common.Config.color.primary

    // Streaming fade: when a new block appears (block count increases), fade it in.
    // We track the last-seen block count separately from the model so the timer only
    // fires on genuine additions, not on per-token content growth within the same block.
    property int _streamBlockCount: 0
    property real _blockFadeOpacity: 1

    onStreamingChanged: {
        _streamBlockCount = streaming ? 0 : 0;
        _blockFadeOpacity = 1;
    }

    onContentBlocksChanged: {
        if (!root.streaming) return;
        const n = root.contentBlocks.length;
        if (n > _streamBlockCount) {
            _streamBlockCount = n;
            _blockFadeOpacity = 0;
            blockFadeTimer.restart();
        }
    }

    Timer {
        id: blockFadeTimer
        interval: 16
        onTriggered: root._blockFadeOpacity = 1
    }

    // Parse content into blocks (text paragraphs and code).
    // Text sections are split on double-newlines so each paragraph gets its own
    // block — this lets the streaming fade trigger per paragraph, not just per
    // code fence.  Handles partial/unclosed fences mid-stream.
    function textToBlocks(raw) {
        return raw.split(/\n\n+/)
            .map(s => s.trim())
            .filter(s => s.length > 0)
            .map(s => ({ type: "text", content: s }));
    }

    readonly property var contentBlocks: {
        const blocks = [];
        const text = content;
        const codeBlockRegex = /```(\w*)\n([\s\S]*?)```/g;
        let lastIndex = 0;
        let match;

        while ((match = codeBlockRegex.exec(text)) !== null) {
            if (match.index > lastIndex) {
                const textBefore = text.substring(lastIndex, match.index).trim();
                if (textBefore) blocks.push(...textToBlocks(textBefore));
            }
            blocks.push({
                type: "code",
                language: match[1] || "txt",
                content: match[2].replace(/\n$/, ""),
                completed: true
            });
            lastIndex = match.index + match[0].length;
        }

        if (lastIndex < text.length) {
            const remaining = text.substring(lastIndex);
            // Check for an unclosed opening fence (streaming mid-block)
            const fenceIdx = remaining.search(/```\w*\n/);
            if (fenceIdx >= 0) {
                const textBefore = remaining.substring(0, fenceIdx).trim();
                if (textBefore) blocks.push(...textToBlocks(textBefore));
                const afterFence = remaining.substring(fenceIdx);
                const langMatch = afterFence.match(/^```(\w*)\n/);
                const lang = langMatch ? (langMatch[1] || "txt") : "txt";
                const codeContent = afterFence.substring(langMatch ? langMatch[0].length : 4).replace(/\n$/, "");
                blocks.push({ type: "code", language: lang, content: codeContent, completed: false });
            } else {
                const trimmed = remaining.trim();
                if (trimmed) blocks.push(...textToBlocks(trimmed));
            }
        }

        if (blocks.length === 0 && text.trim()) {
            blocks.push(...textToBlocks(text));
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
                        capitalization: Font.AllUppercase
                    }
                    opacity: 0.5
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                  visible: root.editing
                  opacity: root.editing ? 1.0 : 0.0
                  color: Qt.alpha(Common.Config.color.error, 0.12)
                  radius: 4
                  implicitHeight: editLabel.implicitHeight + 8
                  implicitWidth: editLabel.implicitWidth + 16

                  Behavior on opacity { NumberAnimation { duration: 150 } }

                  Text {
                    id: editLabel
                    anchors.centerIn: parent
                    text: "EDITING"
                    font.pixelSize: 10
                    font.family: Common.Config.fontFamily
                    font.letterSpacing: 0.5
                    color: Common.Config.color.error
                  }
                }

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

            // In-progress assistant message (placeholder while streaming).
            Item {
                Layout.fillWidth: true
                Layout.topMargin: 6
                visible: root.thinking

                Column {
                    width: parent.width
                    spacing: 4

                    Text {
                        text: "THINKING"
                        color: Common.Config.color.on_surface_variant
                        font {
                            family: Common.Config.fontFamily
                            pixelSize: 9
                            weight: Font.Bold
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
                                    running: root.thinking && root.visible && root.QsWindow.window && root.QsWindow.window.visible
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

            // Content blocks — always live, including during streaming.
            // contentBlocks handles partial fences so markdown renders cleanly mid-stream.
            Repeater {
                model: (!root.thinking && !root.editing && root.renderMarkdown) ? root.contentBlocks : []

                Loader {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.topMargin: index === 0 ? 0 : 1

                    opacity: (root.streaming && index === root.contentBlocks.length - 1)
                        ? root._blockFadeOpacity : 1

                    Behavior on opacity {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }

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
                            text: root.renderMarkdown
                                ? String(modelData.content).replace(/\n/g, "  \n")
                                : modelData.content
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
                visible: !root.thinking && !root.editing && !root.renderMarkdown
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

            // Image attachment thumbnails (user messages with attached images)
            Flow {
                visible: root.isUser && root.attachmentList.length > 0
                spacing: 6
                Layout.fillWidth: true
                Layout.topMargin: 6

                Repeater {
                    model: root.attachmentList
                    Rectangle {
                        required property var modelData
                        width: 80; height: 80; radius: 6; clip: true
                        color: Common.Config.color.surface_container_highest

                        Image {
                            anchors.fill: parent
                            source: modelData.b64 ? "data:" + modelData.mime + ";base64," + modelData.b64 : ""
                            fillMode: Image.PreserveAspectCrop
                        }
                    }
                }
            }

            // Per-message stream metrics (assistant messages, shown after streaming completes)
            Text {
                property var metricsData: {
                    try { return JSON.parse(root.metrics) } catch(e) { return {} }
                }
                property int metricsTokens: metricsData.output_tokens || 0
                property int metricsTtft: metricsData.ttft_ms || 0

                visible: root.isAssistant && root.done && !root.thinking && metricsTokens > 0
                text: metricsTtft > 0
                    ? metricsTtft + "ms ttft  ·  " + metricsTokens + " tok"
                    : metricsTokens + " tok"
                color: Common.Config.color.on_surface_variant
                opacity: 0.45
                font.pixelSize: 10
                font.family: Common.Config.fontFamily
                Layout.topMargin: 4
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
