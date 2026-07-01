import QtQuick
import ".." as Common

Button {
  id: root

  property int type: 0
  property color containerColor: root.type === Enum.ibtFilled ? Common.Config.color.primary : root.type === Enum.ibtFilledTonal ? Common.Config.color.primary_container : "transparent"
  property color contentColor: root.type === Enum.ibtFilled ? Common.Config.color.on_primary : root.type === Enum.ibtFilledTonal ? Common.Config.color.on_primary_container : Common.Config.color.on_surface
  property color disabledContainerColor: root.type === Enum.ibtDefault ? "transparent" : Qt.alpha(Common.Config.color.on_surface, 0.12)
  property color disabledContentColor: Qt.alpha(Common.Config.color.on_surface, 0.38)
  property int elevation: root.down ? 1 : (root.type === Enum.ibtDefault ? 0 : 2)
  property bool elevationVisible: root.type !== Enum.ibtDefault
  property int iconPixelSize: Common.Config.type.titleMedium.size
  property color rippleColor: root.contentColor
  readonly property real implicitBackgroundSize: Math.max(implicitBackgroundWidth, implicitBackgroundHeight)

  implicitWidth: Math.max(40, implicitBackgroundSize > 0 ? implicitBackgroundSize : 40)
  implicitHeight: Math.max(40, implicitBackgroundSize > 0 ? implicitBackgroundSize : 40)

  contentItem: Text {
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    font.family: Common.Config.iconFontFamily
    font.pixelSize: root.iconPixelSize
    text: root.text
    color: root.enabled ? root.contentColor : root.disabledContentColor
  }

  background: ElevationRectangle {
    implicitWidth: root.implicitBackgroundSize
    implicitHeight: root.implicitBackgroundSize
    radius: Math.max(height / 2, 0)
    color: root.enabled ? root.containerColor : root.disabledContainerColor
    elevation: root.elevation
    elevationVisible: root.elevationVisible

    HybridRipple {
      anchors.fill: parent
      radius: Math.max(height / 2, 0)
      pressX: root.pressX
      pressY: root.pressY
      pressed: root.pressed
      stateOpacity: root.down ? Common.Config.state.pressedOpacity : (root.hovered ? Common.Config.state.hoverOpacity : 0)
      color: root.rippleColor
    }
  }
}
