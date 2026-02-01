import QtQuick
import QtQuick.Layouts
import ".."

/**
 * Current Design - pulse dot + title
 */
RowLayout {
  id: root

  property string title: ""

  Layout.fillWidth: true
  spacing: Config.space.sm

  Rectangle {
    id: pulse
    Layout.alignment: Qt.AlignVCenter
    color: Config.color.primary
    Layout.preferredHeight: Config.space.sm
    Layout.preferredWidth: Config.space.sm
    opacity: 0.9
    radius: Config.shape.corner.xs
  }

  Text {
    color: Config.color.on_surface
    elide: Text.ElideRight
    font.family: Config.fontFamily
    font.pixelSize: Config.type.titleSmall.size
    font.weight: Config.type.titleSmall.weight
    text: root.title
  }

  Item { Layout.fillWidth: true }
}
