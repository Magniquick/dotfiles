import QtQuick
import ".."

Item {
  id: root
  property real value: 0
  property color trackColor: Config.color.surfaceVariant
  property color fillColor: Config.color.primary
  property int barHeight: 6

  implicitWidth: 180
  implicitHeight: root.barHeight

  Rectangle {
    id: track
    anchors.fill: parent
    radius: root.barHeight / 2
    color: root.trackColor
    opacity: 0.9
  }

  Rectangle {
    id: fill
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(0, Math.min(1, root.value)) * parent.width
    height: parent.height
    radius: track.radius
    color: root.fillColor
  }
}
