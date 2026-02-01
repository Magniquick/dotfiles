import QtQuick
import QtQuick.Layouts
import ".."

/**
 * Design 4: Minimal
 * - Just title text, slightly larger
 * - No dot or decoration
 */
RowLayout {
  id: root

  property string title: ""

  Layout.fillWidth: true
  spacing: Config.space.sm

  Text {
    text: root.title
    color: Config.color.on_surface
    font.family: Config.fontFamily
    font.pixelSize: Config.type.titleMedium.size
    font.weight: Font.Medium
  }

  Item { Layout.fillWidth: true }
}
