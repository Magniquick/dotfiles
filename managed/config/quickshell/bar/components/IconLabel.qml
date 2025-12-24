import QtQuick
import ".."

Text {
  color: Config.textColor
  font.family: Config.iconFontFamily
  font.pixelSize: Config.iconSize
  elide: Text.ElideRight
  maximumLineCount: 1
  verticalAlignment: Text.AlignVCenter
}
