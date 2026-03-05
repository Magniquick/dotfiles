import QtQuick
import QtQuick.Shapes

Shape {
  id: root
  asynchronous: false
  preferredRendererType: Shape.CurveRenderer

  property real progress: 0
  property real arcRadius: Math.max(0, Math.min(width, height) / 2 - strokeWidth)
  property real strokeWidth: 2
  property color strokeColor: "#ffffff"
  property int capStyle: ShapePath.RoundCap

  readonly property real clampedProgress: Math.max(0, Math.min(1, Number(progress) || 0))

  visible: clampedProgress > 0

  ShapePath {
    strokeWidth: root.strokeWidth
    strokeColor: root.strokeColor
    fillColor: "transparent"
    capStyle: root.capStyle
    joinStyle: ShapePath.RoundJoin

    startX: root.width / 2
    startY: root.height / 2 - root.arcRadius

    PathAngleArc {
      centerX: root.width / 2
      centerY: root.height / 2
      radiusX: root.arcRadius
      radiusY: root.arcRadius
      startAngle: -90
      sweepAngle: 360 * root.clampedProgress
    }
  }
}
