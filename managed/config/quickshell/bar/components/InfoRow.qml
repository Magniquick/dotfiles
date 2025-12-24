import QtQuick
import QtQuick.Layouts
import ".."

RowLayout {
  id: root
  property string label: ""
  property string value: ""
  property string icon: ""
  property color labelColor: Config.textMuted
  property color valueColor: Config.textColor
  property color iconColor: Config.textMuted
  property color leaderColor: Config.tooltipBorder
  property real leaderOpacity: 0.3
  property bool showLeader: true

  spacing: Config.space.sm

  IconLabel {
    visible: root.icon !== ""
    text: root.icon
    color: root.iconColor
    font.pixelSize: Config.type.labelMedium.size
    font.weight: Config.type.labelMedium.weight
    Layout.alignment: Qt.AlignVCenter
  }

  Text {
    text: root.label
    color: root.labelColor
    font.family: Config.fontFamily
    font.pixelSize: Config.type.bodySmall.size
    font.weight: Config.type.bodySmall.weight
    Layout.alignment: Qt.AlignVCenter
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: 1
    Layout.alignment: Qt.AlignVCenter
    color: root.leaderColor
    opacity: root.showLeader ? root.leaderOpacity : 0
    radius: 1
    visible: root.showLeader
  }

  Text {
    text: root.value
    color: root.valueColor
    font.family: Config.fontFamily
    font.pixelSize: Config.type.bodySmall.size
    font.weight: Config.type.bodySmall.weight
    horizontalAlignment: Text.AlignRight
    Layout.alignment: Qt.AlignVCenter
  }
}
