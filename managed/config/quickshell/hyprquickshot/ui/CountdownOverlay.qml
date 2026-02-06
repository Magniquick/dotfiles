pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root

    required property var colors
    required property point center
    required property int value
    required property bool active

    anchors.fill: parent
    opacity: root.active ? 1 : 0
    visible: opacity > 0.01

    function pulse() {
        countdownPulse.restart();
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 180
            easing.type: Easing.InOutQuad
        }
    }

    Rectangle {
        id: countdownCircle

        border.color: Qt.alpha(root.colors.primary, 0.6)
        border.width: 2
        color: Qt.alpha(root.colors.surface, 0.8)
        height: 140
        radius: 70
        scale: 1.0
        width: 140
        x: root.center.x - width / 2
        y: root.center.y - height / 2
    }

    NumberAnimation {
        id: countdownPulse

        duration: 320
        easing.type: Easing.OutCubic
        from: 0.8
        property: "scale"
        target: countdownCircle
        to: 1.08
    }

    Text {
        anchors.centerIn: countdownCircle
        color: root.colors.on_surface
        font.bold: true
        font.pixelSize: 64
        text: root.value
    }
}

