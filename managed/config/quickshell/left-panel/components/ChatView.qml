import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import "../common" as Common
import "./" as Components

Item {
  id: root
  property ListModel messages
  property bool busy: false
  property string modelId: ""
  property bool connectionOnline: true
  property string moodIcon: "\uf4c4"
  property string moodName: "Assistant"

  signal sendRequested(string text)
  signal commandTriggered(string command)

  function positionToEnd() {
    messageList.positionViewAtEnd();
  }

  function copyAllMessages() {
    const lines = [];
    for (let i = 0; i < messages.count; i++) {
      const msg = messages.get(i);
      if (msg.body.includes("Chat history cleared") || msg.body.startsWith("Mood:")) continue;
      const name = msg.sender === "user" ? "user" : root.moodName.toLowerCase();
      lines.push(`*${name}*: ${msg.body}`);
    }
    copyAllProc.command = ["wl-copy", lines.join("\n")];
    copyAllProc.running = true;
  }

  Process {
    id: copyAllProc
  }

  Item {
    id: chatArea
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: composerArea.top

    HoverHandler {
      id: chatAreaHover
    }

    Rectangle {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Common.Config.space.md
      anchors.rightMargin: Common.Config.space.md
      z: 10
      width: 28
      height: 28
      radius: Common.Config.shape.corner.sm
      color: copyAllArea.containsMouse ? Qt.alpha(Common.Config.textMuted, 0.2) : Qt.alpha(Common.Config.surface, 0.9)
      border.width: 1
      border.color: Common.Config.outline
      visible: chatAreaHover.hovered && root.messages && root.messages.count > 0
      opacity: chatAreaHover.hovered ? 1 : 0

      Behavior on opacity {
        NumberAnimation { duration: 150 }
      }

      Text {
        anchors.centerIn: parent
        text: "\udb80\udd8f"
        color: copyAllArea.containsMouse ? Common.Config.textColor : Common.Config.textMuted
        font.family: Common.Config.iconFontFamily
        font.pixelSize: 14
      }

      MouseArea {
        id: copyAllArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.copyAllMessages()
      }
    }

    ListView {
      id: messageList
      anchors.fill: parent
      anchors.margins: Common.Config.space.md
      spacing: Common.Config.space.sm
      clip: true
      model: root.messages

      ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AlwaysOff
        width: 6
        background: Rectangle {
          color: "transparent"
        }
        contentItem: Rectangle {
          implicitWidth: 6
          radius: 3
          color: Common.Config.outline
          opacity: 0.5
        }
      }

      delegate: Components.ChatMessage {
        required property string sender
        required property string body

        readonly property bool isUser: sender === "user"

        width: messageList.width - Common.Config.space.md
        role: sender
        content: body
        bubbleColor: isUser ? Common.Config.m3.info : Common.Config.surfaceContainerHigh
        textColor: isUser ? Common.Config.onPrimary : Common.Config.textColor
        accentColor: Common.Config.primary
        moodIcon: root.moodIcon
      }

      footer: Item {
        width: messageList.width
        height: root.busy ? 60 : 0
        visible: root.busy

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Common.Config.space.md
          anchors.verticalCenter: parent.verticalCenter
          spacing: Common.Config.space.sm
          visible: root.busy

          Rectangle {
            width: 36
            height: 36
            radius: Common.Config.shape.corner.md
            color: Qt.alpha(Common.Config.primary, 0.1)
            border.width: 2
            border.color: Qt.alpha(Common.Config.primary, 0.2)

            Text {
              anchors.centerIn: parent
              text: root.moodIcon
              color: Common.Config.primary
              font.family: Common.Config.iconFontFamily
              font.pixelSize: 18

              SequentialAnimation on opacity {
                running: root.busy
                loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 400 }
                NumberAnimation { to: 1.0; duration: 400 }
              }
            }
          }

          Rectangle {
            height: 40
            width: 80
            radius: Common.Config.shape.corner.lg
            color: Common.Config.surfaceContainerHigh
            border.width: 1
            border.color: Common.Config.outline

            Row {
              anchors.centerIn: parent
              spacing: 4

              Repeater {
                model: 3
                Rectangle {
                  required property int index
                  width: 6
                  height: 6
                  radius: 3
                  color: Common.Config.textMuted

                  SequentialAnimation on opacity {
                    running: root.busy
                    loops: Animation.Infinite
                    PauseAnimation { duration: index * 150 }
                    NumberAnimation { to: 0.3; duration: 300 }
                    NumberAnimation { to: 1.0; duration: 300 }
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
    height: 90

    Components.ChatComposer {
      id: composer
      anchors.fill: parent
      anchors.margins: Common.Config.space.md
      busy: root.busy
      placeholderText: root.connectionOnline ? "Engage System Core..." : "Offline - use /model to switch"
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
