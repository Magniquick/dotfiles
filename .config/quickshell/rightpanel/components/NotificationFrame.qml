import QtQuick
import "../../common/materialkit" as MK
import "../../common" as Common

MK.ClickableSurface {
  id: root

  property int paddingLeft: 16
  property int paddingRight: 16
  property int paddingTop: 14
  property int paddingBottom: 14
  property int frameRadius: 16
  // Hairline outline. The old thick border made cards feel flat.
  property int frameBorderWidth: 1
  property color frameColor: Common.Config.color.surface_container_high
  // Strict parity with bar module borders.
  property color frameBorderColor: Qt.alpha(Common.Config.color.outline_variant, 0.42)
  // Conventional "card" depth. Tuned by callers (list vs popup).
  property int elevation: 0

  default property alias contentData: contentHost.data

  backgroundColor: "transparent"
  hoverBackgroundColor: "transparent"
  pressedBackgroundColor: "transparent"
  implicitHeight: contentHost.implicitHeight + paddingTop + paddingBottom
  radius: root.frameRadius
  rippleColor: Common.Config.color.on_surface
  rippleStateOpacity: root.hovered ? Common.Config.state.hoverOpacity : 0

  MK.ElevationRectangle {
    anchors.fill: parent
    color: root.frameColor
    corners: MK.Util.corners(root.frameRadius)
    elevation: root.elevation
  }

  Rectangle {
    anchors.fill: parent
    color: "transparent"
    radius: root.frameRadius
    border.width: root.frameBorderWidth
    border.color: root.frameBorderColor
  }

  Item {
    id: contentHost
    implicitHeight: childrenRect.height
    height: implicitHeight
    width: parent.width - root.paddingLeft - root.paddingRight
    anchors {
      left: parent.left
      right: parent.right
      top: parent.top
      leftMargin: root.paddingLeft
      rightMargin: root.paddingRight
      topMargin: root.paddingTop
    }
  }
}
