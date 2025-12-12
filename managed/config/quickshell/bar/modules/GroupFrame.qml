import QtQuick
import "../theme"

Rectangle {
  id: root
  color: Theme.colors.base
  radius: Theme.radius
  implicitHeight: Math.max(content.implicitHeight + Theme.groupPadY * 2, Theme.barHeight)
  implicitWidth: content.implicitWidth + Theme.groupPadX * 2

  default property alias contentData: content.data

  Row {
    id: content
    anchors {
      fill: parent
      leftMargin: Theme.groupPadX
      rightMargin: Theme.groupPadX
      topMargin: Theme.groupPadY
      bottomMargin: Theme.groupPadY
    }
    spacing: Theme.spacing
  }
}
