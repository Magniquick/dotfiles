import QtQuick
import ".."

Row {
  id: root
  property string iconText: ""
  property string text: ""
  property color iconColor: Config.textColor
  property color textColor: Config.textColor
  property int iconPixelSize: Config.iconSize
  property int textPixelSize: Config.fontSize
  spacing: Config.moduleSpacing

  IconLabel {
    text: root.iconText
    color: root.iconColor
    font.pixelSize: root.iconPixelSize
  }

  BarLabel {
    text: root.text
    color: root.textColor
    font.pixelSize: root.textPixelSize
  }
}
