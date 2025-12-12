import QtQuick
import "../theme"

Rectangle {
  id: root
  color: Theme.colors.base
  radius: Theme.radius
  implicitHeight: Math.max(content.implicitHeight + Theme.modulePadY * 2, Theme.barHeight)
  implicitWidth: content.implicitWidth + Theme.modulePadX * 2

  property bool flat: false

  // Leave margin handling to parent rows. Toggle padding when embedded in groups.
  property int padX: Theme.modulePadX
  property int padY: Theme.modulePadY

  default property alias contentData: content.data

  Row {
    id: content
    anchors {
      fill: parent
      leftMargin: padX
      rightMargin: padX
      topMargin: padY
      bottomMargin: padY
    }
    spacing: Theme.spacing
  }
}
