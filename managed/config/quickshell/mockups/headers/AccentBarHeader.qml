import QtQuick
import QtQuick.Layouts
import ".."

/**
 * Design 3: Accent Bar
 * - Left accent bar (3px)
 * - Title to the right
 */
RowLayout {
  id: root

  property string title: ""

  Layout.fillWidth: true
  spacing: Config.space.sm

  Rectangle {
    Layout.preferredWidth: 3
    Layout.preferredHeight: titleText.implicitHeight
    radius: 1.5
    color: Config.color.primary
  }

  Text {
    id: titleText
    text: root.title
    color: Config.color.on_surface
    font.family: Config.fontFamily
    font.pixelSize: Config.type.titleSmall.size
    font.weight: Config.type.titleSmall.weight
  }

  Item { Layout.fillWidth: true }
}
