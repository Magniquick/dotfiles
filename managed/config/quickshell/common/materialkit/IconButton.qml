import QtQuick

Button {
  id: root

  property int type: 0
  readonly property real implicitBackgroundSize: Math.max(implicitBackgroundWidth, implicitBackgroundHeight)

  implicitWidth: Math.max(40, implicitBackgroundSize > 0 ? implicitBackgroundSize : 40)
  implicitHeight: Math.max(40, implicitBackgroundSize > 0 ? implicitBackgroundSize : 40)
}
