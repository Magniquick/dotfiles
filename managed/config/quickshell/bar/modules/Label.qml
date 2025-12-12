import QtQuick
import "../theme"

Text {
  font.family: Theme.fontFamily
  font.pixelSize: Theme.fontSize
  color: Theme.colors.text
  renderType: Text.NativeRendering
  verticalAlignment: Text.AlignVCenter
  elide: Text.ElideRight
}
