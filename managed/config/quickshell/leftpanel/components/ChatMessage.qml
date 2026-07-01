pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qsmath 1.0
import "../../bar/components" as BarComponents
import "../../common" as Common
import "../../common/components" as CommonComponents

Item {
  id: root
  property int messageIndex: -1
  property string role: "assistant"
  property string content: ""
  property string modelLabel: ""
  property string moodIcon: "\uf4c4"
  property string moodName: "Assistant"
  property bool showHeader: true
  property bool done: true
  property bool thinking: false
  property bool streaming: false

  property bool editing: false
  property bool renderMarkdown: true
  property string activeSelectionKey: ""
  property var metrics: ({})
  property var attachments: []

  property var attachmentList: normalizedAttachments(root.attachments)
  property Item actionTooltipTarget: null
  property Item pendingActionTooltipTarget: null
  property string actionTooltipText: ""
  property string pendingActionTooltipText: ""
  property bool actionTooltipOpen: false

  signal regenerateRequested
  signal deleteRequested
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

  MarkdownStreamModel {
    id: markdownModel
    content: root.content
    streaming: root.streaming
  }

  onStreamingChanged: {
    markdownModel.streaming = root.streaming
    _streamBlockCount = streaming ? 0 : 0
    _blockFadeOpacity = 1
  }

  Connections {
    target: markdownModel
    function onBlockCountChanged() {
      if (!root.streaming)
        return
      const n = markdownModel.blockCount
      if (n > root._streamBlockCount) {
        root._streamBlockCount = n
        root._blockFadeOpacity = 0
        blockFadeTimer.restart()
      }
    }
  }

  Timer {
    id: blockFadeTimer
    interval: 16
    onTriggered: root._blockFadeOpacity = 1
  }

  onActiveSelectionKeyChanged: {
    if (!activeSelectionKey.startsWith(selectionPrefix) && sourceView.selectedText.length > 0)
      sourceView.deselect()
  }

  function containsMath(text) {
    const source = String(text || "")
    return /(^|[^\\])\$[^\s$][\s\S]*?[^\\]\$/.test(source) || /\\\([\s\S]+?\\\)/.test(source) || /\$\$[\s\S]+?\$\$/.test(source) || /\\\[[\s\S]+?\\\]/.test(source) || /\\begin\{(?:equation\*?|align\*?|gather\*?|multline\*?|matrix\*?|bmatrix|pmatrix|vmatrix|Vmatrix)\}[\s\S]+?\\end\{(?:equation\*?|align\*?|gather\*?|multline\*?|matrix\*?|bmatrix|pmatrix|vmatrix|Vmatrix)\}/.test(source)
  }

  function normalizedAttachments(value) {
    if (!value)
      return []
    if (Array.isArray(value))
      return value
    if (typeof value.length === "number") {
      const items = []
      for (let i = 0; i < value.length; i++)
        items.push(value[i])
      return items
    }
    if (Array.from) {
      try {
        return Array.from(value)
      } catch (e) {
        return []
      }
    }
    return []
  }

  function startEditing() {
    root.editing = true
    fullEditArea.text = root.content
    fullEditArea.forceActiveFocus()
  }

  function toggleSourceView() {
    root.renderMarkdown = !root.renderMarkdown
  }

  function attachmentSource(attachment) {
    if (!attachment)
      return ""
    const path = String(attachment.path || "").trim()
    if (path.length > 0)
      return "file://" + path
    const mime = String(attachment.mime || "").trim()
    const b64 = String(attachment.b64 || "").trim()
    if (mime.length > 0 && b64.length > 0)
      return "data:" + mime + ";base64," + b64
    return ""
  }

  function showActionTooltip(target, text) {
    root.pendingActionTooltipTarget = target
    root.pendingActionTooltipText = text
    root.actionTooltipOpen = false
    actionTooltipDelay.restart()
  }

  function hideActionTooltip(target) {
    if (root.pendingActionTooltipTarget === target) {
      actionTooltipDelay.stop()
      root.pendingActionTooltipTarget = null
      root.pendingActionTooltipText = ""
    }
    if (root.actionTooltipTarget === target) {
      root.actionTooltipOpen = false
      root.actionTooltipTarget = null
      root.actionTooltipText = ""
    }
  }

  function updateActionTooltip(target, text) {
    if (root.actionTooltipTarget === target)
      root.actionTooltipText = text
    if (root.pendingActionTooltipTarget === target)
      root.pendingActionTooltipText = text
  }

  Timer {
    id: actionTooltipDelay
    interval: 400
    onTriggered: {
      root.actionTooltipTarget = root.pendingActionTooltipTarget
      root.actionTooltipText = root.pendingActionTooltipText
      root.actionTooltipOpen = !!root.actionTooltipTarget && root.actionTooltipText.length > 0
    }
  }

  Component {
    id: actionTooltipContent

    Text {
      color: Common.Config.color.on_surface
      font.family: Common.Config.fontFamily
      font.pixelSize: Common.Config.type.labelMedium.size
      font.weight: Common.Config.type.labelMedium.weight
      text: root.actionTooltipText
    }
  }

  BarComponents.TooltipPopup {
    contentComponent: actionTooltipContent
    enabled: root.actionTooltipTarget !== null && root.actionTooltipText.length > 0
    hoverable: false
    open: root.actionTooltipOpen
    targetItem: root.actionTooltipTarget
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
        visible: root.showHeader
        Layout.preferredHeight: visible ? implicitHeight : 0
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

        Item {
          Layout.fillWidth: true
        }

        Rectangle {
          visible: root.editing
          opacity: root.editing ? 1.0 : 0.0
          color: Qt.alpha(Common.Config.color.error, 0.12)
          radius: 4
          implicitHeight: editLabel.implicitHeight + 8
          implicitWidth: editLabel.implicitWidth + 16

          Behavior on opacity {
            NumberAnimation {
              duration: 150
            }
          }

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
            NumberAnimation {
              duration: 150
            }
          }

          MessageControlButton {
            id: regenerateButton
            visible: root.isAssistant && root.done
            icon: "\uea77"
            onClicked: root.regenerateRequested()
            onHoveredChanged: hovered ? root.showActionTooltip(regenerateButton, qsTr("Regenerate")) : root.hideActionTooltip(regenerateButton)
          }

          MessageControlButton {
            id: copyBtn
            property bool copied: false
            icon: copied ? "\ueab2" : "\uebcc"
            activated: copied
            onCopiedChanged: root.updateActionTooltip(copyBtn, copied ? qsTr("Copied") : qsTr("Copy"))
            onClicked: {
              Quickshell.clipboardText = root.content
              copied = true
              copyTimer.restart()
            }
            Timer {
              id: copyTimer
              interval: 1500
              onTriggered: copyBtn.copied = false
            }
            onHoveredChanged: hovered ? root.showActionTooltip(copyBtn, copied ? qsTr("Copied") : qsTr("Copy")) : root.hideActionTooltip(copyBtn)
          }

          MessageControlButton {
            id: editButton
            visible: root.done
            icon: "\uea73"
            activated: root.editing
            onHoveredChanged: hovered ? root.showActionTooltip(editButton, root.editing ? qsTr("Save") : qsTr("Edit")) : root.hideActionTooltip(editButton)
            onClicked: {
              if (root.editing) {
                root.editSaved(fullEditArea.text)
                root.editing = false
              } else {
                root.startEditing()
              }
              root.updateActionTooltip(editButton, root.editing ? qsTr("Save") : qsTr("Edit"))
            }
          }

          MessageControlButton {
            id: sourceButton
            icon: "\ueac4"
            activated: !root.renderMarkdown
            onHoveredChanged: hovered ? root.showActionTooltip(sourceButton, root.renderMarkdown ? qsTr("Source") : qsTr("Render")) : root.hideActionTooltip(sourceButton)
            onClicked: {
              root.toggleSourceView()
              root.updateActionTooltip(sourceButton, root.renderMarkdown ? qsTr("Source") : qsTr("Render"))
            }
          }

          MessageControlButton {
            id: deleteButton
            icon: "\uea81"
            onClicked: root.deleteRequested()
            onHoveredChanged: hovered ? root.showActionTooltip(deleteButton, qsTr("Delete")) : root.hideActionTooltip(deleteButton)
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
                  PauseAnimation {
                    duration: typingDot.index * 200
                  }
                  NumberAnimation {
                    to: 0.2
                    duration: 400
                  }
                  NumberAnimation {
                    to: 1.0
                    duration: 400
                  }
                }
              }
            }
          }
        }
      }

      // Content blocks — always live, including during streaming.
      Repeater {
        id: contentRepeater
        model: (!root.thinking && !root.editing && root.renderMarkdown) ? markdownModel : 0

        Loader {
          id: contentBlockLoader
          required property int blockId
          required property string kind
          required property string type
          required property string content
          required property string raw
          required property string display
          required property bool completed
          required property string language
          required property int index

          Layout.fillWidth: true
          Layout.topMargin: index === 0 ? 0 : 1

          opacity: (root.streaming && index === markdownModel.blockCount - 1) ? root._blockFadeOpacity : 1

          Behavior on opacity {
            NumberAnimation {
              duration: 220
              easing.type: Easing.OutCubic
            }
          }

          sourceComponent: type === "code" ? codeBlockComponent : textBlockComponent

          Component {
            id: codeBlockComponent
            MessageCodeBlock {
              selectionKey: root.selectionPrefix + "block-" + contentBlockLoader.blockId
              activeSelectionKey: root.activeSelectionKey
              code: contentBlockLoader.content
              language: contentBlockLoader.language
              editing: false
              onSelectionActivated: selectionKey => root.selectionActivated(selectionKey)
            }
          }

          Component {
            id: textBlockComponent
            Item {
              id: textBlockRoot
              property string selectionKey: root.selectionPrefix + "block-" + contentBlockLoader.blockId
              readonly property bool textMarkdownReady: root.renderMarkdown && contentBlockLoader.completed
              readonly property bool useMathRenderer: root.renderMarkdown && root.containsMath(contentBlockLoader.display)
              property var mathBlockItem: mathBlockLoader.item
              implicitWidth: useMathRenderer && mathBlockItem ? mathBlockItem.implicitWidth : textBlock.implicitWidth
              implicitHeight: useMathRenderer && mathBlockItem ? mathBlockItem.implicitHeight : textBlock.implicitHeight

              function clearSelection() {
                if (useMathRenderer) {
                  if (mathBlockItem && mathBlockItem.clearSelection)
                    mathBlockItem.clearSelection()
                } else if (textBlock.selectedText.length > 0) {
                  textBlock.deselect()
                }
              }

              onSelectionKeyChanged: {
                if (root.activeSelectionKey !== selectionKey)
                  clearSelection()
              }

              Connections {
                target: root
                function onActiveSelectionKeyChanged() {
                  if (root.activeSelectionKey !== textBlockRoot.selectionKey)
                    textBlockRoot.clearSelection()
                }
              }

              CommonComponents.SelectableTextBlock {
                id: textBlock
                anchors.fill: parent
                visible: !textBlockRoot.useMathRenderer
                readonly property bool markdownReady: textBlockRoot.textMarkdownReady
                text: markdownReady ? String(contentBlockLoader.display).replace(/\n/g, "  \n") : contentBlockLoader.display
                textFormat: markdownReady ? TextEdit.MarkdownText : TextEdit.PlainText
                font.family: Common.Config.fontFamily
                font.pixelSize: 13
                selectionKey: textBlockRoot.selectionKey
                onSelectionActivated: selectionKey => root.selectionActivated(selectionKey)
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
                  markdown: contentBlockLoader.display
                  rawMarkdown: contentBlockLoader.raw
                  completed: contentBlockLoader.completed
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
      CommonComponents.SelectableTextBlock {
        id: sourceView
        Layout.fillWidth: true
        Layout.topMargin: 2
        visible: !root.thinking && !root.editing && !root.renderMarkdown
        text: root.content
        textFormat: TextEdit.PlainText
        font.family: "monospace"
        font.pixelSize: 12
        linkCursorEnabled: false
        selectionKey: root.selectionPrefix + "source"
        onSelectionActivated: selectionKey => root.selectionActivated(selectionKey)
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
            root.editSaved(fullEditArea.text)
            root.editing = false
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            root.editing = false
            event.accepted = true
          }
        }
      }

      // Image attachment thumbnails (user messages with attached images)
      Flow {
        id: attachmentFlow
        visible: root.isUser && root.attachmentList.length > 0
        spacing: 6
        Layout.fillWidth: true
        Layout.topMargin: 6

        Repeater {
          model: root.attachmentList
          Image {
            id: attachmentPreview
            required property var modelData
            readonly property real maxPreviewWidth: Math.max(1, Math.min(attachmentFlow.width, 500))
            readonly property real maxPreviewHeight: 100
            readonly property real imageAspect: status === Image.Ready && implicitHeight > 0 ? implicitWidth / implicitHeight : 1

            width: status === Image.Ready ? Math.min(maxPreviewWidth, maxPreviewHeight * imageAspect) : 0
            height: status === Image.Ready ? Math.min(maxPreviewHeight, width / imageAspect) : 0
            source: root.attachmentSource(attachmentPreview.modelData)
            fillMode: Image.PreserveAspectFit
            sourceSize.height: maxPreviewHeight
            asynchronous: true
            cache: false
          }
        }
      }

      // Per-message stream metrics (assistant messages, shown after streaming completes)
      Text {
        property var metricsData: root.metrics || ({})
        property int metricsTokens: metricsData.output_tokens || 0
        property int metricsTtft: metricsData.ttf_ms || 0

        visible: root.isAssistant && root.done && !root.thinking && metricsTokens > 0
        text: metricsTtft > 0 ? metricsTtft + "ms ttft  ·  " + metricsTokens + " tok" : metricsTokens + " tok"
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

  HoverHandler {
    id: messageHover
  }
}
