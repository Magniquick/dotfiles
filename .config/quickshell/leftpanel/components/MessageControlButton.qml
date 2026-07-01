import QtQuick
import "../../common/materialkit" as MK
import "../../common" as Common

MK.ClickableSurface {
  id: root
  property string icon: ""
  property bool activated: false

  width: 24
  height: 24
  radius: 6
  backgroundColor: root.activated ? Qt.alpha(Common.Config.color.primary, 0.25) : "transparent"
  disabledOpacity: 0.35
  hoverBackgroundColor: root.backgroundColor
  pressedBackgroundColor: root.backgroundColor
  rippleColor: Common.Config.color.on_surface
  rippleStateOpacity: root.hovered ? Common.Config.state.hoverOpacity : 0
  scale: root.pressed ? 0.92 : 1

  Behavior on scale {
    NumberAnimation {
      duration: 80
      easing.type: Easing.OutCubic
    }
  }

  Text {
    anchors.centerIn: parent
    text: root.icon
    color: root.activated ? Common.Config.color.primary : root.hovered ? Common.Config.color.on_surface : Common.Config.color.on_surface_variant
    font.family: Common.Config.iconFontFamily
    font.pixelSize: 13
    opacity: root.activated ? 1 : 0.85

    Behavior on color {
      ColorAnimation {
        duration: 120
      }
    }
  }
}
