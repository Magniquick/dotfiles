import QtQuick
import ".."

Rectangle {
  id: root
  property bool active: false
  property color activeColor: Config.color.primary
  property color inactiveColor: Config.color.surfaceVariant
  property color hoverColor: Config.color.surfaceContainerHigh
  property color borderColor: Config.color.outline
  property real disabledOpacity: Config.state.disabledOpacity
  property bool hovered: false
  property bool pressed: false
  property bool hoverScaleEnabled: false
  property real hoverScale: 1.02
  signal clicked()
  default property alias content: contentItem.data

  color: root.active ? root.activeColor : (root.hovered ? root.hoverColor : root.inactiveColor)
  border.width: root.active ? 0 : 1
  border.color: root.active ? root.activeColor : root.borderColor
  scale: root.hoverScaleEnabled && root.hovered ? root.hoverScale : 1
  antialiasing: true
  opacity: root.enabled ? 1 : root.disabledOpacity

  Behavior on color {
    ColorAnimation {
      duration: Config.motion.duration.shortMs
      easing.type: Config.motion.easing.standard
    }
  }

  Behavior on border.color {
    ColorAnimation {
      duration: Config.motion.duration.shortMs
      easing.type: Config.motion.easing.standard
    }
  }

  Behavior on scale {
    NumberAnimation {
      duration: Config.motion.duration.shortMs
      easing.type: Config.motion.easing.standard
    }
  }

  Item {
    id: contentItem
    anchors.fill: parent
  }

  Rectangle {
    anchors.fill: parent
    radius: parent.radius
    color: Config.color.onSurface
    opacity: root.pressed ? Config.state.pressedOpacity : (root.hovered ? Config.state.hoverOpacity : 0)
    visible: root.enabled
    antialiasing: true
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: root.hovered = true
    onExited: {
      root.hovered = false
      root.pressed = false
    }
    onPressed: root.pressed = true
    onReleased: root.pressed = false
    onClicked: root.clicked()
  }
}
