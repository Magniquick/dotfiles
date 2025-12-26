import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: button

    property string actionName
    property string icon
    property color accent: ColorPalette.palette.red
    property string selection: ""
    property string hoverAction: ""
    property int strokeWidth: 2
    property bool reveal: false
    property int revealDelay: 0
    property real revealProgress: 0
    property bool mouseEnabled: true

    signal hovered(string actionName)
    signal unhovered(string actionName)
    signal activated(string actionName)

    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
    width: 54
    height: 54
    implicitWidth: width
    implicitHeight: height
    radius: 14
    color: "transparent"
    border.width: 0
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
        anchors.margins: strokeWidth / 2
        radius: Math.max(0, button.radius - strokeWidth / 2)
        color: "transparent"
        border.width: strokeWidth
        border.color: selection === actionName ? accent : "transparent"
        antialiasing: true

        Behavior on border.color {
            ColorAnimation {
                duration: 120
            }
        }
    }

    Text {
        anchors.centerIn: parent
        text: icon
        font.pointSize: 30
        font.family: "JetBrainsMono NFP"
        color: accent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: mouseEnabled
        cursorShape: Qt.PointingHandCursor
        onEntered: button.hovered(button.actionName)
        onExited: button.unhovered(button.actionName)
        onClicked: button.activated(button.actionName)
    }

    SequentialAnimation {
        id: revealIn

        running: false

        PauseAnimation {
            duration: revealDelay
        }

        NumberAnimation {
            target: button
            property: "revealProgress"
            to: 1
            duration: 250
            easing.type: Easing.OutBack
            easing.overshoot: 3
        }
    }

    NumberAnimation {
        id: revealOut

        target: button
        property: "revealProgress"
        to: 0
        duration: 120
        easing.type: Easing.InOutQuad
        running: false
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 220
        }
    }
}
