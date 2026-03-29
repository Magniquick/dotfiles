pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.bar

SpinBox {
  id: root

  implicitHeight: 40
  editable: true

  contentItem: TextInput {
    color: Config.color.on_surface
    font.family: Config.fontFamily
    font.pixelSize: Config.type.bodyMedium.size
    horizontalAlignment: Qt.AlignHCenter
    padding: Config.space.sm
    readOnly: !root.editable
    selectByMouse: true
    text: root.displayText
    validator: root.validator
    verticalAlignment: TextInput.AlignVCenter

    onEditingFinished: root.valueModified()
  }

  up.indicator: Rectangle {
    implicitWidth: 28
    implicitHeight: parent.height / 2
    color: root.up.pressed ? Qt.alpha(Config.color.primary, 0.2) : "transparent"

    Text {
      anchors.centerIn: parent
      color: Config.color.on_surface_variant
      font.family: Config.iconFontFamily
      font.pixelSize: Config.type.labelSmall.size
      text: "󰅀"
    }
  }

  down.indicator: Rectangle {
    implicitWidth: 28
    implicitHeight: parent.height / 2
    color: root.down.pressed ? Qt.alpha(Config.color.primary, 0.2) : "transparent"

    Text {
      anchors.centerIn: parent
      color: Config.color.on_surface_variant
      font.family: Config.iconFontFamily
      font.pixelSize: Config.type.labelSmall.size
      text: "󰅂"
    }
  }

  background: Rectangle {
    radius: Config.shape.corner.sm
    color: Qt.tint(Config.barPopupSurface, Qt.alpha(Config.color.surface_container_high, 0.9))
    border.width: root.activeFocus ? 1.5 : 1
    border.color: root.activeFocus ? Config.color.primary : Qt.alpha(Config.color.outline_variant, 0.75)
  }
}
