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
    property bool thinking: false
    property bool streaming: false

    property bool editing: false
    property bool renderMarkdown: true
    property string activeSelectionKey: ""
    property var metrics: ({})
    property var attachments: []

    property var attachmentList: Array.isArray(root.attachments) ? root.attachments : []

    signal regenerateRequested()
    signal deleteRequested()
    signal editSaved(string newContent)
    signal selectionActivated(string selectionKey)

    readonly property bool isAssistant: role === "assistant"
    readonly property bool isUser: role === "user"
    readonly property color accentColor: isUser ? Common.Config.color.primary : Common.Config.color.primary
    readonly property string selectionPrefix: "message-" + root.messageIndex + ":"

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

    onActiveSelectionKeyChanged: {
        if (!activeSelectionKey.startsWith(selectionPrefix) && sourceView.selectedText.length > 0)
            sourceView.deselect();
    }

    // Parse content into larger text/code runs. Keeping contiguous prose in a
    // single block preserves cross-paragraph text selection, while the final
    // in-progress text run can stay plain during streaming to avoid markdown
    // re-layout jitter on every token.
    function pushTextBlock(blocks, raw, completed) {
        const normalized = String(raw || "").replace(/^\n+|\n+$/g, "");
        if (normalized.length === 0)
            return;
        blocks.push({
            type: "text",
            content: normalized,
            completed: completed
        });
    }

    readonly property var contentBlocks: {
        const blocks = [];
        const text = content;
        const codeBlockRegex = /```(\w*)\n([\s\S]*?)```/g;
        let lastIndex = 0;
        let match;

        while ((match = codeBlockRegex.exec(text)) !== null) {
            if (match.index > lastIndex) {
                pushTextBlock(blocks, text.substring(lastIndex, match.index), true);
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
                pushTextBlock(blocks, remaining.substring(0, fenceIdx), true);
                const afterFence = remaining.substring(fenceIdx);
                const langMatch = afterFence.match(/^```(\w*)\n/);
                const lang = langMatch ? (langMatch[1] || "txt") : "txt";
                const codeContent = afterFence.substring(langMatch ? langMatch[0].length : 4).replace(/\n$/, "");
                blocks.push({ type: "code", language: lang, content: codeContent, completed: false });
            } else {
                pushTextBlock(blocks, remaining, !root.streaming);
            }
        }

        if (blocks.length === 0 && text.trim()) {
            pushTextBlock(blocks, text, !root.streaming);
        }

        return blocks;
    }

    function containsMath(text) {
        const source = String(text || "");
        return /(^|[^\\])\$[^\s$][\s\S]*?[^\\]\$/.test(source)
            || /\\\([\s\S]+?\\\)/.test(source)
            || /\$\$[\s\S]+?\$\$/.test(source)
            || /\\\[[\s\S]+?\\\]/.test(source)
            || /\\begin\{(?:equation\*?|align\*?|gather\*?|multline\*?|matrix\*?|bmatrix|pmatrix|vmatrix|Vmatrix)\}[\s\S]+?\\end\{(?:equation\*?|align\*?|gather\*?|multline\*?|matrix\*?|bmatrix|pmatrix|vmatrix|Vmatrix)\}/.test(source);
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
                                    running: root.thinking && root.visible
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
                id: contentRepeater
                model: (!root.thinking && !root.editing && root.renderMarkdown)
                    ? root.contentBlocks : []

                Loader {
                    id: contentBlockLoader
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
                            selectionKey: root.selectionPrefix + "block-" + contentBlockLoader.index
                            activeSelectionKey: root.activeSelectionKey
                            code: contentBlockLoader.modelData.content
                            language: contentBlockLoader.modelData.language
                            editing: false
                            onSelectionActivated: selectionKey => root.selectionActivated(selectionKey)
                        }
                    }

                    Component {
                        id: textBlockComponent
                        Item {
                            id: textBlockRoot
                            property string selectionKey: root.selectionPrefix + "block-" + contentBlockLoader.index
                            readonly property bool markdownReady: root.renderMarkdown
                                && contentBlockLoader.modelData.completed
                            readonly property bool useMathRenderer: markdownReady
                                && root.containsMath(contentBlockLoader.modelData.content)
                            property var mathBlockItem: mathBlockLoader.item
                            implicitWidth: useMathRenderer && mathBlockItem
                                ? mathBlockItem.implicitWidth
                                : textBlock.implicitWidth
                            implicitHeight: useMathRenderer && mathBlockItem
                                ? mathBlockItem.implicitHeight
                                : textBlock.implicitHeight

                            function clearSelection() {
                                if (useMathRenderer) {
                                    if (mathBlockItem && mathBlockItem.clearSelection)
                                        mathBlockItem.clearSelection();
                                } else if (textBlock.selectedText.length > 0) {
                                    textBlock.deselect();
                                }
                            }

                            onSelectionKeyChanged: {
                                if (root.activeSelectionKey !== selectionKey)
                                    clearSelection();
                            }

                            Connections {
                                target: root
                                function onActiveSelectionKeyChanged() {
                                    if (root.activeSelectionKey !== textBlockRoot.selectionKey)
                                        textBlockRoot.clearSelection();
                                }
                            }

                            TextEdit {
                                id: textBlock
                                anchors.fill: parent
                                visible: !textBlockRoot.useMathRenderer
                                readonly property bool markdownReady: textBlockRoot.markdownReady
                                text: markdownReady
                                    ? String(contentBlockLoader.modelData.content).replace(/\n/g, "  \n")
                                    : contentBlockLoader.modelData.content
                                textFormat: markdownReady ? TextEdit.MarkdownText : TextEdit.PlainText
                                color: Common.Config.color.on_surface
                                wrapMode: TextEdit.Wrap
                                font.family: Common.Config.fontFamily
                                font.pixelSize: 13
                                readOnly: true
                                selectByMouse: true
                                cursorVisible: false
                                activeFocusOnPress: false

                                onLinkActivated: link => Qt.openUrlExternally(link)
                                onSelectedTextChanged: {
                                    if (selectedText.length > 0)
                                        root.selectionActivated(textBlockRoot.selectionKey);
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.NoButton
                                    hoverEnabled: true
                                    cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor
                                }
                            }

                            Loader {
                                id: mathBlockLoader
                                anchors.fill: parent
                                active: textBlockRoot.useMathRenderer
                                visible: active

                                sourceComponent: mathBlockComponent
                            }

                            Component {
                                id: mathBlockComponent
                                MessageMathBlock {
                                    markdown: contentBlockLoader.modelData.content
                                    completed: contentBlockLoader.modelData.completed
                                    selectionKey: textBlockRoot.selectionKey
                                    activeSelectionKey: root.activeSelectionKey
                                    onSelectionActivated: selectionKey => root.selectionActivated(selectionKey)
                                }
                            }
                        }
                    }
                }
            }

            // Raw markdown/source view
            TextEdit {
                id: sourceView
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

                onSelectedTextChanged: {
                    if (selectedText.length > 0)
                        root.selectionActivated(root.selectionPrefix + "source");
                }
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
                        id: attachmentPreview
                        required property var modelData
                        width: 80; height: 80; radius: 6; clip: true
                        color: Common.Config.color.surface_container_highest

                        Image {
                            anchors.fill: parent
                            source: attachmentPreview.modelData.b64 ? "data:" + attachmentPreview.modelData.mime + ";base64," + attachmentPreview.modelData.b64 : ""
                            fillMode: Image.PreserveAspectCrop
                        }
                    }
                }
            }

            // Per-message stream metrics (assistant messages, shown after streaming completes)
            Text {
                property var metricsData: root.metrics || ({})
                property int metricsTokens: metricsData.output_tokens || 0
                property int metricsTtft: metricsData.ttf_ms || 0

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
