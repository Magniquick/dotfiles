import QtQuick
import ".."

Item {
  id: root
  property real value: 0
  property real minimum: 0
  property real maximum: 1
  property color trackColor: Config.color.surfaceVariant
  property color fillColor: Config.color.primary
  property color knobColor: Config.color.primary
  property int barHeight: 6
  property int knobSize: 14
  property int snapSteps: 0
  property bool dragging: false
  property real dragValue: NaN
  readonly property real displayValue: (root.dragging && !isNaN(root.dragValue))
    ? root.dragValue
    : root.value
  signal userChanged(real value)

  implicitHeight: Math.max(root.barHeight, root.knobSize)
  implicitWidth: 180
  opacity: root.enabled ? 1 : 0.5

  function clampedRatio() {
    if (root.maximum <= root.minimum)
      return 0
    const ratio = (root.displayValue - root.minimum) / (root.maximum - root.minimum)
    return Math.max(0, Math.min(1, ratio))
  }

  function valueFromPosition(xPos) {
    if (width <= 0)
      return root.minimum
    const ratio = Math.max(0, Math.min(1, xPos / width))
    return root.minimum + ratio * (root.maximum - root.minimum)
  }

  function snappedValue(value) {
    if (root.snapSteps <= 1)
      return value
    const stepSize = (root.maximum - root.minimum) / (root.snapSteps - 1)
    if (stepSize <= 0)
      return root.minimum
    const snapped = Math.round((value - root.minimum) / stepSize) * stepSize + root.minimum
    return Math.max(root.minimum, Math.min(root.maximum, snapped))
  }

  function updateFromPosition(xPos) {
    const next = snappedValue(valueFromPosition(xPos))
    root.dragValue = next
    root.userChanged(next)
  }

  Rectangle {
    id: track
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: root.barHeight
    radius: root.barHeight / 2
    color: root.trackColor
  }

  Rectangle {
    id: fill
    anchors.verticalCenter: track.verticalCenter
    width: track.width * root.clampedRatio()
    height: track.height
    radius: track.radius
    color: root.fillColor
  }

  Rectangle {
    id: knob
    width: root.knobSize
    height: root.knobSize
    radius: root.knobSize / 2
    x: (track.width * root.clampedRatio()) - (root.knobSize / 2)
    y: (height - root.knobSize) / 2
    color: root.knobColor
    border.width: 1
    border.color: Config.color.outline
    antialiasing: true
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onPressed: {
      root.dragging = true
      root.updateFromPosition(mouse.x)
    }
    onPositionChanged: if (root.dragging) root.updateFromPosition(mouse.x)
    onReleased: {
      root.dragging = false
      root.dragValue = NaN
    }
  }
}
