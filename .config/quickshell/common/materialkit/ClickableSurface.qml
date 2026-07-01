import QtQuick

Rectangle {
  id: root

  default property alias content: contentItem.data
  property color backgroundColor: "transparent"
  property color hoverBackgroundColor: root.backgroundColor
  property color pressedBackgroundColor: root.hoverBackgroundColor
  property real disabledOpacity: 1
  property bool hovered: false
  property bool pressed: false
  property color rippleColor: "white"
  property bool rippleStateLayerEnabled: true
  property real rippleStateOpacity: root.hovered ? 0.08 : 0
  property bool rippleWaveEnabled: true
  property int acceptedButtons: Qt.LeftButton
  property int cursorShape: Qt.PointingHandCursor
  property bool wheelEnabled: false

  signal clicked(var mouse)
  signal wheeled(var wheel)

  antialiasing: true
  color: root.pressed ? root.pressedBackgroundColor : (root.hovered ? root.hoverBackgroundColor : root.backgroundColor)
  opacity: root.enabled ? 1 : root.disabledOpacity

  onEnabledChanged: {
    if (!enabled) {
      hovered = false
      pressed = false
    }
  }

  Behavior on color {
    ColorAnimation {
      duration: 120
      easing.type: Easing.OutCubic
    }
  }

  Item {
    id: contentItem

    anchors.fill: parent
    z: 1
  }

  HybridRipple {
    anchors.fill: parent
    color: root.rippleColor
    pressX: pointerArea.pressX
    pressY: pointerArea.pressY
    pressed: pointerArea.pressed
    radius: root.radius
    stateLayerEnabled: root.rippleStateLayerEnabled
    stateOpacity: root.rippleStateOpacity
    waveEnabled: root.rippleWaveEnabled
    z: 2
  }

  MouseArea {
    id: pointerArea

    property real pressX: width / 2
    property real pressY: height / 2

    anchors.fill: parent
    acceptedButtons: root.acceptedButtons
    cursorShape: root.enabled ? root.cursorShape : Qt.ArrowCursor
    hoverEnabled: root.enabled
    z: 0

    onClicked: function (mouse) {
      if (root.enabled)
        root.clicked(mouse)
    }
    onCanceled: root.pressed = false
    onEntered: root.hovered = true
    onExited: {
      root.hovered = false
      root.pressed = false
    }
    onPressed: mouse => {
      pressX = mouse.x
      pressY = mouse.y
      root.pressed = true
    }
    onReleased: root.pressed = false
    onWheel: wheel => {
      if (!root.enabled || !root.wheelEnabled) {
        wheel.accepted = false
        return
      }
      root.wheeled(wheel)
    }
  }
}
