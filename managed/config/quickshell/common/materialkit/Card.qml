import QtQuick

Pane {
  id: root

  property int type: 0
  property color borderColor: Qt.alpha("black", 0.16)
  property int borderWidth: type === 1 ? 1 : 0

  background: Rectangle {
    color: root.backgroundColor
    radius: root.radius
    border.color: root.borderColor
    border.width: root.borderWidth
  }
}
