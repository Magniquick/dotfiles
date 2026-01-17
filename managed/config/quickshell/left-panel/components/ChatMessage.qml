import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../common" as Common

Item {
  id: root
  property string role: "assistant"
  property string content: ""
  property color bubbleColor: Common.Config.surfaceContainerHigh
  property color textColor: Common.Config.textColor
  property color accentColor: Common.Config.primary
  property string moodIcon: "\uf4c4"

  readonly property bool isAssistant: role === "assistant"
  readonly property bool hasListItems: content.includes("\n- ") || content.includes("\n* ") || content.startsWith("- ") || content.startsWith("* ")

  implicitHeight: messageRow.implicitHeight
  implicitWidth: parent ? parent.width : 300

  RowLayout {
    id: messageRow
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Common.Config.space.md
    layoutDirection: root.isAssistant ? Qt.LeftToRight : Qt.RightToLeft

    // Avatar
    Rectangle {
      Layout.alignment: Qt.AlignTop
      width: 36
      height: 36
      radius: Common.Config.shape.corner.md
      color: root.isAssistant ? Qt.alpha(root.accentColor, 0.1) : Common.Config.surfaceContainerHighest
      border.width: 2
      border.color: root.isAssistant ? Qt.alpha(root.accentColor, 0.2) : Common.Config.outline

      Text {
        anchors.centerIn: parent
        text: root.isAssistant ? root.moodIcon : "\uf4ff" // mood icon / nf-md-account
        color: root.isAssistant ? root.accentColor : Common.Config.m3.info
        font.family: Common.Config.iconFontFamily
        font.pixelSize: 18
      }
    }

    // Message bubble
    Rectangle {
      id: bubble
      Layout.maximumWidth: root.width * 0.75
      Layout.minimumWidth: Math.min(messageText.implicitWidth + Common.Config.space.md * 2, Layout.maximumWidth)

      implicitHeight: messageText.contentHeight + Common.Config.space.sm * 2
      implicitWidth: Math.min(messageText.contentWidth + Common.Config.space.md * 2, Layout.maximumWidth)

      color: root.bubbleColor
      radius: Common.Config.shape.corner.md
      border.width: 1
      border.color: root.isAssistant ? Common.Config.outline : root.bubbleColor

      property bool hovered: false

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        propagateComposedEvents: true
        onEntered: bubble.hovered = true
        onExited: bubble.hovered = false
        onPressed: mouse => mouse.accepted = false
      }

      TextEdit {
        id: messageText
        anchors.fill: parent
        anchors.leftMargin: root.hasListItems ? -30 : Common.Config.space.md
        anchors.rightMargin: Common.Config.space.md
        anchors.topMargin: Common.Config.space.sm
        anchors.bottomMargin: Common.Config.space.xs
        text: root.content
        textFormat: TextEdit.MarkdownText
        color: root.textColor
        wrapMode: TextEdit.Wrap
        font.family: Common.Config.fontFamily
        font.pixelSize: Common.Config.type.bodyMedium.size
        font.weight: Common.Config.type.bodyMedium.weight
        readOnly: true
        selectByMouse: false
        cursorVisible: false
        activeFocusOnPress: false
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        bottomPadding: 0
        textMargin: 0
      }

      Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Common.Config.space.xs
        anchors.rightMargin: Common.Config.space.xs
        width: 24
        height: 24
        radius: Common.Config.shape.corner.sm
        color: copyArea.containsMouse ? Qt.alpha(Common.Config.textMuted, 0.2) : Qt.alpha(Common.Config.surface, 0.9)
        border.width: 1
        border.color: Common.Config.outline
        visible: bubble.hovered
        opacity: bubble.hovered ? 1 : 0

        Behavior on opacity {
          NumberAnimation { duration: 150 }
        }

        Text {
          anchors.centerIn: parent
          text: "\uf0c5" // nf-fa-copy
          color: copyArea.containsMouse ? Common.Config.textColor : Common.Config.textMuted
          font.family: Common.Config.iconFontFamily
          font.pixelSize: 11
        }

        MouseArea {
          id: copyArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            copyProc.command = ["wl-copy", root.content];
            copyProc.running = true;
          }
        }
      }

      Process {
        id: copyProc
      }
    }

    // Spacer to push content
    Item {
      Layout.fillWidth: true
    }
  }
}
