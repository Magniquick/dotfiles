import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
  id: root
  property string label: ""
  property string value: ""
  property string icon: ""
  property color labelColor: Config.textMuted
  property color valueColor: Config.textColor
  property color accentColor: Config.accent
  property color backgroundColor: Config.moduleBackgroundHover
  property color borderColor: Config.tooltipBorder
  property bool showFill: true
  property real fillRatio: 0
  property int padding: 8
  property int barHeight: 3

  radius: Math.max(8, Config.tooltipRadius - 6)
  color: root.backgroundColor
  border.width: 1
  border.color: root.borderColor
  antialiasing: true

  implicitWidth: contentLayout.implicitWidth + root.padding * 2
  implicitHeight: contentLayout.implicitHeight + root.padding * 2 + (root.showFill ? root.barHeight + 2 : 0)

  ColumnLayout {
    id: contentLayout
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.padding
    anchors.rightMargin: root.padding
    anchors.topMargin: root.padding
    anchors.bottomMargin: root.padding + (root.showFill ? root.barHeight + 2 : 0)
    spacing: 2

    RowLayout {
      spacing: 6
      Layout.fillWidth: true

      IconLabel {
        visible: root.icon !== ""
        text: root.icon
        color: root.labelColor
        font.pixelSize: Math.max(10, Config.iconSize - 3)
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        text: root.label
        color: root.labelColor
        font.family: Config.fontFamily
        font.pixelSize: Math.max(10, Config.fontSize - 3)
        Layout.alignment: Qt.AlignVCenter
      }

      Item { Layout.fillWidth: true }
    }

    Text {
      text: root.value
      color: root.valueColor
      font.family: Config.fontFamily
      font.pixelSize: Math.max(11, Config.fontSize)
      Layout.alignment: Qt.AlignVCenter
    }
  }

  Rectangle {
    visible: root.showFill
    height: root.barHeight
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    color: root.borderColor
    opacity: 0.28
    radius: root.barHeight / 2
  }

  Rectangle {
    visible: root.showFill
    height: root.barHeight
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    width: Math.max(2, Math.min(1, root.fillRatio)) * parent.width
    color: root.accentColor
    radius: root.barHeight / 2
  }
}
