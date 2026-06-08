import ".."
import QtQuick

Text {
  color: Config.color.on_surface
  elide: Text.ElideRight
  font.family: Config.fontFamily
  font.pixelSize: Config.type.bodyMedium.size
  font.weight: Font.Medium
  font.variableAxes: Config.fontVariableAxes(Config.type.bodyMedium.size, Font.Medium)
  maximumLineCount: 1
  verticalAlignment: Text.AlignVCenter
}
