import QtQuick
import ".."

Text {
  color: Config.textColor
  font.family: Config.fontFamily
  font.pixelSize: Config.type.bodyMedium.size
  font.weight: Config.type.bodyMedium.weight
  elide: Text.ElideRight
  maximumLineCount: 1
  verticalAlignment: Text.AlignVCenter
}
