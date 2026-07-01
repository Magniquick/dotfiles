import QtQuick
import QtQuick.Layouts
import "common/materialkit" as MK
import "common" as Common

MK.ElevationRectangle {
  id: button

  property color accent: Common.Config.color.error
  property string actionName
  property string hoverAction: ""
  property string icon
  property bool mouseEnabled: true
  property bool reveal: false
  property int revealDelay: 0
  property real revealProgress: 0
  property string selection: ""
  property int strokeWidth: 2

  signal activated(string actionName)
  signal hoverEntered(string actionName)
  signal hoverExited(string actionName)

  Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
  color: "transparent"
  height: 54
  implicitHeight: height
  implicitWidth: width
  opacity: {
    var base = 1
    if (selection !== "")
      base = selection === actionName ? 1 : 0.35
    else if (hoverAction !== "")
      base = hoverAction === actionName ? 1 : 0.5
    return base
  }
  scale: revealProgress
  transformOrigin: Item.Center
  width: 54
  radius: 14

  Behavior on opacity {
    NumberAnimation {
      duration: Common.Config.motion.duration.longMs
    }
  }

  onRevealChanged: {
    revealIn.stop()
    revealOut.stop()
    if (reveal)
      revealIn.start()
    else
      revealOut.start()
  }

  Rectangle {
    id: stroke

    anchors.fill: parent
    anchors.margins: button.strokeWidth / 2
    antialiasing: true
    border.color: button.selection === button.actionName ? button.accent : "transparent"
    border.width: button.strokeWidth
    color: "transparent"
    radius: Math.max(0, button.radius - button.strokeWidth / 2)

    Behavior on border.color {
      ColorAnimation {
        duration: Common.Config.motion.duration.shortMs
      }
    }
  }
  Text {
    anchors.centerIn: parent
    color: button.accent
    font.family: Common.Config.iconFontFamily
    font.pointSize: 30
    horizontalAlignment: Text.AlignHCenter
    text: button.icon
    verticalAlignment: Text.AlignVCenter
  }
  MK.ClickableSurface {
    anchors.fill: parent
    clip: true
    radius: button.radius
    enabled: button.mouseEnabled
    backgroundColor: "transparent"
    hoverBackgroundColor: "transparent"
    pressedBackgroundColor: "transparent"
    rippleColor: button.accent
    rippleStateOpacity: 0

    onClicked: button.activated(button.actionName)
    onHoveredChanged: {
      if (!button.mouseEnabled)
        return
      if (hovered)
        button.hoverEntered(button.actionName)
      else
        button.hoverExited(button.actionName)
    }
  }
  SequentialAnimation {
    id: revealIn

    running: false

    PauseAnimation {
      duration: button.revealDelay
    }
    NumberAnimation {
      duration: Common.Config.motion.duration.longMs
      easing.overshoot: 3
      easing.type: Easing.OutBack
      property: "revealProgress"
      target: button
      to: 1
    }
  }
  NumberAnimation {
    id: revealOut

    duration: Common.Config.motion.duration.shortMs
    easing.type: Easing.InOutQuad
    property: "revealProgress"
    running: false
    target: button
    to: 0
  }
}
