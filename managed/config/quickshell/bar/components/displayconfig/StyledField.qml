pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.bar

TextField {
  id: root

  implicitHeight: 40
  color: Config.color.on_surface
  font.family: Config.fontFamily
  font.pixelSize: Config.type.bodyMedium.size
  leftPadding: Config.space.sm
  rightPadding: Config.space.sm
  placeholderTextColor: Qt.alpha(Config.color.on_surface_variant, 0.8)
  selectedTextColor: Config.color.on_primary
  selectionColor: Config.color.primary
  verticalAlignment: Text.AlignVCenter

  background: Rectangle {
    radius: Config.shape.corner.sm
    color: Qt.tint(Config.barPopupSurface, Qt.alpha(Config.color.surface_container_high, 0.9))
    border.width: activeFocus ? 1.5 : 1
    border.color: activeFocus ? Config.color.primary : Qt.alpha(Config.color.outline_variant, 0.75)

    Behavior on border.color {
      ColorAnimation {
        duration: Config.motion.duration.shortMs
      }
    }
  }
}
