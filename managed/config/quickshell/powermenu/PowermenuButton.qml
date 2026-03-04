import QtQuick
import QtQuick.Layouts
import "./materialkit" as MK
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
        var base = 1;
        if (selection !== "")
            base = selection === actionName ? 1 : 0.35;
        else if (hoverAction !== "")
            base = hoverAction === actionName ? 1 : 0.5;
        return base;
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
        revealIn.stop();
        revealOut.stop();
        if (reveal)
            revealIn.start();
        else
            revealOut.start();
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
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: button.radius
        clip: true

        MK.HybridRipple {
            anchors.fill: parent
            color: button.accent
            pressX: buttonMouseArea.pressX
            pressY: buttonMouseArea.pressY
            pressed: buttonMouseArea.pressed
            radius: button.radius
            stateOpacity: 0
        }
    }
    MouseArea {
        id: buttonMouseArea
        property real pressX: width / 2
        property real pressY: height / 2
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: button.mouseEnabled

        onClicked: button.activated(button.actionName)
        onEntered: button.hoverEntered(button.actionName)
        onExited: button.hoverExited(button.actionName)
        onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
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
