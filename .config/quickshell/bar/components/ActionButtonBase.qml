import ".."
import "../../common/materialkit" as MK
import QtQuick

MK.ClickableSurface {
  id: root

  property bool active: false
  property color activeColor: Config.color.primary
  property color borderColor: Config.color.outline
  property color hoverColor: Config.color.surface_container_high
  property real hoverScale: 1.02
  property bool hoverScaleEnabled: false
  property color inactiveColor: Config.color.surface_variant

  antialiasing: true
  backgroundColor: root.active ? root.activeColor : root.inactiveColor
  border.color: root.active ? root.activeColor : root.borderColor
  border.width: root.active ? 0 : 1
  disabledOpacity: Config.state.disabledOpacity
  hoverBackgroundColor: root.active ? root.activeColor : root.hoverColor
  pressedBackgroundColor: root.hoverBackgroundColor
  rippleColor: Config.color.on_surface
  rippleStateLayerEnabled: false
  rippleStateOpacity: 0
  scale: root.hoverScaleEnabled && root.hovered ? root.hoverScale : 1

  Behavior on border.color {
    ColorAnimation {
      duration: Config.motion.duration.shortMs
      easing.type: Config.motion.easing.standard
    }
  }
  Behavior on scale {
    NumberAnimation {
      duration: Config.motion.duration.shortMs
      easing.type: Config.motion.easing.standard
    }
  }
}
