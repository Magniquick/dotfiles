import QtQuick
import "../../common/materialkit" as MK
import "../../common" as Common

MK.ClickableSurface {
  id: root

  property string label: ""
  property string icon: ""

  radius: Common.Config.shape.corner.sm
  backgroundColor: Common.Config.color.surface_variant
  hoverBackgroundColor: Common.Config.color.surface_variant
  pressedBackgroundColor: Common.Config.color.surface_variant
  rippleColor: Common.Config.color.on_surface
  rippleStateOpacity: root.hovered ? Common.Config.state.hoverOpacity : 0
  implicitHeight: Common.Config.space.xl
  implicitWidth: contentRow.implicitWidth + Common.Config.space.md * 2

  Row {
    id: contentRow
    anchors.centerIn: parent
    spacing: Common.Config.space.xs

    Text {
      visible: root.icon.length > 0
      text: root.icon
      color: Common.Config.color.on_surface
      font.family: Common.Config.iconFontFamily
      font.pixelSize: Common.Config.type.labelMedium.size
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      text: root.label
      color: Common.Config.color.on_surface
      font.family: Common.Config.fontFamily
      font.pixelSize: Common.Config.type.labelMedium.size
      font.weight: Common.Config.type.labelMedium.weight
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}
