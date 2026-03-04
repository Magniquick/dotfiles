import QtQuick

Item {
  id: root

  property color color: "transparent"
  property real radius: 0
  property var corners: null
  property int elevation: 0
  property bool elevationVisible: true

  readonly property real resolvedRadius: {
    if (corners && corners.radius !== undefined)
      return Math.max(0, Number(corners.radius) || 0);
    return Math.max(0, Number(radius) || 0);
  }

  implicitWidth: fillRect.implicitWidth
  implicitHeight: fillRect.implicitHeight

  Rectangle {
    id: shadowRect

    anchors.fill: fillRect
    anchors.margins: -Math.max(0, root.elevation * 1.5)
    color: "black"
    radius: root.resolvedRadius + Math.max(0, root.elevation)
    opacity: root.elevationVisible ? Math.min(0.22, root.elevation * 0.08) : 0
    visible: root.elevationVisible && root.elevation > 0
    z: -1
  }

  Rectangle {
    id: fillRect

    anchors.fill: parent
    color: root.color
    radius: root.resolvedRadius
  }
}
