import QtQuick
import QtQuick.Controls as T

T.Pane {
  id: root

  property color backgroundColor: "transparent"
  property real radius: 0

  padding: 0

  background: Rectangle {
    color: root.backgroundColor
    radius: root.radius
  }
}
