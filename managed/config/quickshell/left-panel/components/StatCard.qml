import QtQuick
import QtQuick.Layouts
import "../common" as Common

Item {
  id: root
  property string title: ""
  property string value: ""
  property string icon: ""
  property color accent: Common.Config.primary
  property bool compact: false

  implicitHeight: compact ? 48 : 90
  Layout.fillWidth: true

  Rectangle {
    id: card
    anchors.fill: parent
    color: Common.Config.m3.surfaceContainerHigh
    radius: Common.Config.shape.corner.md
    border.width: 1
    border.color: cardArea.containsMouse ? root.accent : Common.Config.m3.outline
    opacity: cardArea.containsMouse ? 1.0 : 0.8

    Behavior on border.color { ColorAnimation { duration: Common.Config.motion.duration.shortMs } }
    Behavior on opacity { NumberAnimation { duration: Common.Config.motion.duration.shortMs } }

    MouseArea {
      id: cardArea
      anchors.fill: parent
      hoverEnabled: true
    }

    RowLayout {
      visible: root.compact
      anchors.fill: parent
      anchors.margins: Common.Config.space.sm
      spacing: Common.Config.space.sm

      Text {
        text: root.icon
        color: root.accent
        font.family: Common.Config.iconFontFamily
        font.pixelSize: 14
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        spacing: 0
        Text {
          text: root.title
          color: Common.Config.textMuted
          font { family: Common.Config.fontFamily; pixelSize: 8; weight: Font.Black; letterSpacing: 1; capitalization: Font.AllUppercase }
        }
        Text {
          text: root.value
          color: Common.Config.textColor
          font { family: Common.Config.fontFamily; pixelSize: 12; weight: Font.Medium }
        }
      }
    }

    ColumnLayout {
      visible: !root.compact
      anchors.fill: parent
      anchors.margins: Common.Config.space.md
      spacing: 0

      RowLayout {
        Layout.fillWidth: true
        Text {
          text: root.icon
          color: root.accent
          font.family: Common.Config.iconFontFamily
          font.pixelSize: 16
        }
        Item { Layout.fillWidth: true }
        Text {
          text: root.title
          color: Common.Config.textMuted
          font { family: Common.Config.fontFamily; pixelSize: 9; weight: Font.Black; letterSpacing: 1.2; capitalization: Font.AllUppercase }
          opacity: 0.6
        }
      }

      Item { Layout.fillHeight: true }

      Text {
        text: root.value
        color: Common.Config.textColor
        font { family: Common.Config.fontFamily; pixelSize: Common.Config.type.titleLarge.size; weight: Font.Medium }
        Layout.alignment: Qt.AlignLeft
      }
    }
  }
}
