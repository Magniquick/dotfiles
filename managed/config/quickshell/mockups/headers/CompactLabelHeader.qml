import QtQuick
import QtQuick.Layouts
import ".."

/**
 * Design 1: Compact Label
 * - Small tinted badge
 * - ALL_CAPS title, letter-spacing, bold
 * - Underline accent bar
 */
ColumnLayout {
  id: root

  property string title: ""

  Layout.fillWidth: true
  spacing: Config.space.xs

  RowLayout {
    spacing: Config.space.sm

    // Small tinted badge
    Rectangle {
      Layout.preferredWidth: 16
      Layout.preferredHeight: 16
      radius: Config.shape.corner.xs
      color: Qt.alpha(Config.color.primary, 0.15)

      Rectangle {
        anchors.centerIn: parent
        width: 6
        height: 6
        radius: 3
        color: Config.color.primary
      }
    }

    // ALL CAPS title
    Text {
      text: root.title.toUpperCase()
      color: Config.color.on_surface
      font.family: Config.fontFamily
      font.pixelSize: 11
      font.weight: Font.Black
      font.letterSpacing: 1.8
    }

    Item { Layout.fillWidth: true }
  }

  // Accent underline bar
  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: 2
    radius: 1
    color: Config.color.primary
    opacity: 0.6
  }
}
