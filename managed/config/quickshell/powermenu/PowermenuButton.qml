import QtQuick
import QtQuick.Layouts

Rectangle {
    id: button

    property color accent: ColorPalette.palette.red
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
    signal hovered(string actionName)
    signal unhovered(string actionName)

    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
    border.width: 0
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
    radius: 14
    scale: revealProgress
    transformOrigin: Item.Center
    width: 54

    Behavior on opacity {
        NumberAnimation {
            duration: 220
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
                duration: 120
            }
        }
    }
    Text {
        anchors.centerIn: parent
        color: button.accent
        font.family: "JetBrainsMono NFP"
        font.pointSize: 30
        horizontalAlignment: Text.AlignHCenter
        text: button.icon
        verticalAlignment: Text.AlignVCenter
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: button.mouseEnabled

        onClicked: button.activated(button.actionName)
        onEntered: button.hovered(button.actionName)
        onExited: button.unhovered(button.actionName)
    }
    SequentialAnimation {
        id: revealIn

        running: false

        PauseAnimation {
            duration: button.revealDelay
        }
        NumberAnimation {
            duration: 250
            easing.overshoot: 3
            easing.type: Easing.OutBack
            property: "revealProgress"
            target: button
            to: 1
        }
    }
    NumberAnimation {
        id: revealOut

        duration: 120
        easing.type: Easing.InOutQuad
        property: "revealProgress"
        running: false
        target: button
        to: 0
    }
}
