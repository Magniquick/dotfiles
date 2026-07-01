import QtQuick
import QtQuick.Controls as T
import "../" as Common

T.ScrollBar {
  id: root

  implicitWidth: 4
  implicitHeight: 4
  padding: 0

  background: Rectangle {
    color: "transparent"
  }

  contentItem: Rectangle {
    implicitWidth: 4
    implicitHeight: 4
    radius: Math.min(width, height) / 2
    color: Qt.alpha(Common.Config.color.primary, root.active || root.hovered || root.pressed ? 0.48 : 0.28)

    Behavior on color {
      ColorAnimation {
        duration: Common.Config.motion.duration.shortMs
        easing.type: Common.Config.motion.easing.standard
      }
    }
  }
}
