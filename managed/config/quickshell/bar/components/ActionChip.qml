import QtQuick
import ".."

ActionButtonBase {
  id: root
  property string text: ""

  radius: height / 2
  implicitHeight: Config.space.xl + Config.space.xs
  implicitWidth: label.implicitWidth + Config.space.xl
  hoverScaleEnabled: true

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    color: root.active ? Config.textColor : Config.textMuted
    font.family: Config.fontFamily
    font.pixelSize: Config.type.labelMedium.size
    font.weight: Config.type.labelMedium.weight
  }
}
