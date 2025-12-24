import QtQuick
import ".."

ActionButtonBase {
  id: root
  property string icon: ""

  width: Config.space.xl + Config.space.sm
  height: Config.space.xl + Config.space.sm
  radius: width / 2
  disabledOpacity: Config.state.disabledOpacity

  Text {
    anchors.centerIn: parent
    text: root.icon
    color: root.active ? Config.textColor : Config.textMuted
    font.family: Config.iconFontFamily
    font.pixelSize: Config.type.titleMedium.size
  }
}
