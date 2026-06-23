pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
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
  readonly property string emptyStateImage: modelId.indexOf("gemini") >= 0 ? Quickshell.shellPath("leftpanel/assets/Google_Gemini_icon_2025.svg.png") : Quickshell.shellPath("leftpanel/assets/OpenAI-white-monoblossom.svg")

  signal sendRequested(string text, var attachments)
  signal commandTriggered(string command)
  signal regenerateRequested(string messageId)
  signal deleteRequested(string messageId)
  signal editRequested(string messageId, string newContent)

  function positionToEnd() {
    messageList.scrollToEnd()
  }

  function followLatestMessage() {
    messageList.scrollToEnd()
  }

  function copyAllMessages() {
    if (root.chatSession && root.chatSession.copyAllText) {
      Quickshell.clipboardText = root.chatSession.copyAllText()
      return
    }
  }

  function focusComposer() {
    if (composer && composer.focusInput)
      composer.focusInput()
  }

  function clearTextFocus() {
    if (composer && composer.clearFocus)
      composer.clearFocus()
  }

  function setLatestVisibleToolExpanded(expanded) {
    messageList.scrollToEnd()
    for (let i = messageRepeater.count - 1; i >= 0; --i) {
      const item = messageRepeater.itemAt(i)
      if (!item || item["kind"] !== "tool")
        continue
      messageList.setToolRowExpanded(item["_messageId"], item["tool"], expanded)
      return true
    }
    return false
  }

  Shortcut {
    context: Qt.WindowShortcut
    enabled: root.visible
    sequence: "Ctrl+N"
    onActivated: {
      if (messageRepeater.count > 0)
        root.commandTriggered("/clear")
    }
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
        composer.clearFocus()
        mouse.accepted = false
      }
    }

    MK.Pane {
      anchors.fill: parent
      backgroundColor: Common.Config.color.surface_container_low
      radius: Common.Config.shape.corner.md
    }

    Item {
      id: emptyState
      anchors.fill: parent
      anchors.margins: Common.Config.space.xl
      visible: opacity > 0
      opacity: messageRepeater.count === 0 && !root.busy ? 1 : 0
      z: 1

      Item {
        id: emptyStateContent
        anchors.centerIn: parent
        width: Math.min(parent.width, 280)
        height: emptyStateCopy.implicitHeight

        Image {
          id: emptyStateImage
          x: (emptyStateContent.width - width) / 2
          y: emptyStateTitle.y + (emptyStateTitle.height - height) / 2
          width: Math.min(emptyStateContent.width, 270)
          height: width
          source: root.emptyStateImage
          sourceSize.width: width
          sourceSize.height: height
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          opacity: 0.075
        }

        Column {
          id: emptyStateCopy
          anchors.fill: parent
          spacing: Common.Config.space.xs

          Text {
            id: emptyStateTitle
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Start anywhere")
            color: Common.Config.color.on_surface
            font.family: Common.Config.fontFamily
            font.pixelSize: Common.Config.type.titleLarge.size
            font.weight: 760
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            width: parent.width
            text: qsTr("Ask normally, or type / for model, mood, resume, and tools.")
            color: Common.Config.color.on_surface_variant
            font.family: Common.Config.fontFamily
            font.pixelSize: Common.Config.type.bodySmall.size
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
          }

          Item {
            width: 1
            height: Common.Config.spaceHalfXs
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Common.Config.space.xs

            Repeater {
              model: ["/model", "/providers", "/mood", "/resume"]

              delegate: MK.ClickableSurface {
                id: commandChip
                required property string modelData

                width: chipText.implicitWidth + Common.Config.space.sm * 2
                height: 26
                radius: height / 2
                backgroundColor: Qt.alpha(Common.Config.color.on_surface, 0.05)
                hoverBackgroundColor: Qt.alpha(Common.Config.color.primary, 0.14)
                pressedBackgroundColor: Qt.alpha(Common.Config.color.primary, 0.20)
                rippleColor: Common.Config.color.primary
                rippleStateOpacity: commandChip.hovered ? Common.Config.state.hoverOpacity : 0
                border.width: 1
                border.color: commandChip.hovered ? Qt.alpha(Common.Config.color.primary, 0.34) : Qt.alpha(Common.Config.color.on_surface, 0.08)

                onClicked: root.commandTriggered(commandChip.modelData)

                Text {
                  id: chipText
                  anchors.centerIn: parent
                  text: commandChip.modelData
                  color: Qt.alpha(Common.Config.color.on_surface, 0.78)
                  font.family: Common.Config.fontFamily
                  font.pixelSize: Common.Config.type.labelSmall.size
                  font.weight: Common.Config.type.labelSmall.weight
                }
              }
            }
          }
        }
      }

      Behavior on opacity {
        NumberAnimation {
          duration: Common.Config.motion.duration.shortMs
          easing.type: Common.Config.motion.easing.standard
        }
      }
    }

    MK.Flickable {
      id: messageList
      anchors.fill: parent
      anchors.margins: 10
      contentHeight: messageColumn.implicitHeight
      autoHideVerticalScrollBar: true
      property string activeSelectionKey: ""
      property var toolExpansionState: ({})

      function scrollToEnd() {
        Qt.callLater(() => {
          contentY = maxContentY()
        })
      }

      function maxContentY() {
        const maxY = Math.max(0, contentHeight - height)
        return maxY
      }

      function toolRowKey(messageId, tool) {
        const id = String(messageId || "")
        if (id.length > 0)
          return id
        return String((tool || ({})).tool_call_id || "")
      }

      function toolRowExpanded(messageId, tool) {
        const key = toolRowKey(messageId, tool)
        return key.length > 0 && !!toolExpansionState[key]
      }

      function withToolExpansionValue(state, key, value) {
        const next = {}
        for (const existingKey in state)
          next[existingKey] = state[existingKey]
        if (value)
          next[key] = true
        else
          delete next[key]
        return next
      }

      function setToolRowExpanded(messageId, tool, expanded) {
        const key = toolRowKey(messageId, tool)
        if (key.length === 0)
          return
        toolExpansionState = withToolExpansionValue(toolExpansionState, key, expanded)
      }

      Column {
        id: messageColumn
        width: messageList.width
        spacing: 10

        Repeater {
          id: messageRepeater
          model: root.messagesModel

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

            width: messageColumn.width
            implicitHeight: contentLoader.loadedItem ? contentLoader.loadedItem.implicitHeight : 0
            property string _messageId: messageId
            property bool emptyAssistantPlaceholder: kind !== "tool" && sender === "assistant" && String(body || "").trim().length === 0 && !(root.busy && index === (messageRepeater.count - 1))

            Loader {
              id: contentLoader
              readonly property Item loadedItem: item as Item
              width: parent.width
              sourceComponent: delegateRoot.emptyAssistantPlaceholder ? null : (delegateRoot.kind === "tool" ? toolRowComponent : chatMessageComponent)
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
                streaming: root.busy && delegateRoot.sender === "assistant" && delegateRoot.index === (messageRepeater.count - 1)
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
    }

    MK.Button {
      id: scrollToBottomButton
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Common.Config.space.md
      z: 100
      visible: opacity > 0
      opacity: messageList.atYEnd ? 0 : 1
      scale: messageList.atYEnd ? 0.92 : 1
      hoverEnabled: true
      text: "\uf063"
      implicitWidth: scrollToBottomContent.implicitWidth + Common.Config.space.md * 2
      implicitHeight: 36

      contentItem: Item {
        implicitWidth: scrollToBottomContent.implicitWidth
        implicitHeight: scrollToBottomContent.implicitHeight

        Row {
          id: scrollToBottomContent
          anchors.centerIn: parent
          spacing: Common.Config.space.xs

          Text {
            anchors.verticalCenter: parent.verticalCenter
            font.family: Common.Config.iconFontFamily
            font.pixelSize: Common.Config.type.labelLarge.size
            color: Common.Config.color.on_primary_container
            text: scrollToBottomButton.text
            verticalAlignment: Text.AlignVCenter
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            font.family: Common.Config.fontFamily
            font.pixelSize: Common.Config.type.labelMedium.size
            font.weight: Common.Config.type.labelMedium.weight
            color: Common.Config.color.on_primary_container
            text: qsTr("Latest")
            verticalAlignment: Text.AlignVCenter
          }
        }
      }

      background: Rectangle {
        radius: height / 2
        color: Common.Config.color.primary_container

        MK.HybridRipple {
          anchors.fill: parent
          radius: parent.radius
          pressX: scrollToBottomButton.pressX
          pressY: scrollToBottomButton.pressY
          pressed: scrollToBottomButton.pressed
          color: Common.Config.color.on_primary_container
          stateOpacity: scrollToBottomButton.down ? Common.Config.state.pressedOpacity : (scrollToBottomButton.hovered ? Common.Config.state.hoverOpacity : 0)
        }

        Behavior on color {
          ColorAnimation {
            duration: Common.Config.motion.duration.shortMs
            easing.type: Common.Config.motion.easing.standard
          }
        }
      }

      Behavior on opacity {
        NumberAnimation {
          duration: Common.Config.motion.duration.shortMs
          easing.type: Common.Config.motion.easing.standard
        }
      }

      Behavior on scale {
        NumberAnimation {
          duration: Common.Config.motion.duration.shortMs
          easing.type: Common.Config.motion.easing.standard
        }
      }

      onClicked: root.followLatestMessage()
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
      onSend: function (text, attachments) {
        // When we send a message, re-enable following the tail.
        root.followLatestMessage()
        root.sendRequested(text, attachments)
      }
      onCommandTriggered: command => {
        root.followLatestMessage()
        root.commandTriggered(command)
      }
    }
  }
}
