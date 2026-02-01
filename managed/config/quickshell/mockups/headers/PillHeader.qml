import QtQuick
import QtQuick.Layouts
import ".."

/**
 * Design 2: Pill Badge
 * - Title inside a rounded pill chip
 */
RowLayout {
  id: root

  property string title: ""

  Layout.fillWidth: true
  spacing: Config.space.sm

  Rectangle {
    implicitWidth: pillContent.implicitWidth + Config.space.md * 2
    implicitHeight: pillContent.implicitHeight + Config.space.xs * 2
    radius: height / 2
    color: Qt.alpha(Config.color.primary, 0.12)
    border.color: Qt.alpha(Config.color.primary, 0.3)
    border.width: 1

    RowLayout {
      id: pillContent
      anchors.centerIn: parent
      spacing: Config.space.xs

      Rectangle {
        width: 6
        height: 6
        radius: 3
        color: Config.color.primary
      }

      Text {
        text: root.title
        color: Config.color.on_surface
        font.family: Config.fontFamily
        font.pixelSize: Config.type.labelMedium.size
        font.weight: Config.type.labelMedium.weight
      }
    }
  }

  Item { Layout.fillWidth: true }
}
