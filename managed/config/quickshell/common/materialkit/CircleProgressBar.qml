import QtQuick

Item {
  id: root

  property real from: 0
  property real to: 100
  property real value: 0
  property color strokeColor: "#ffffff"
  property real strokeWidth: 2

  readonly property real progress: {
    const low = Number(from) || 0;
    const high = Number(to) || 0;
    const v = Number(value) || 0;
    const span = high - low;
    if (span <= 0)
      return 0;
    return Math.max(0, Math.min(1, (v - low) / span));
  }

  CircleProgressShape {
    anchors.fill: parent
    arcRadius: Math.max(0, Math.min(width, height) / 2 - root.strokeWidth / 2 - 1)
    progress: root.progress
    strokeWidth: root.strokeWidth
    strokeColor: root.strokeColor
  }
}
