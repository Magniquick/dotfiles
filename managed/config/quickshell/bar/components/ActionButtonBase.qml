import ".."
import QtQuick

Rectangle {
    id: root

    property bool active: false
    property color activeColor: Config.m3.primary
    property color borderColor: Config.m3.outline
    default property alias content: contentItem.data
    property real disabledOpacity: Config.state.disabledOpacity
    property color hoverColor: Config.m3.surfaceContainerHigh
    property real hoverScale: 1.02
    property bool hoverScaleEnabled: false
    property bool hovered: false
    property color inactiveColor: Config.m3.surfaceVariant
    property bool pressed: false

    signal clicked

    antialiasing: true
    border.color: root.active ? root.activeColor : root.borderColor
    border.width: root.active ? 0 : 1
    color: root.active ? root.activeColor : (root.hovered ? root.hoverColor : root.inactiveColor)
    opacity: root.enabled ? 1 : root.disabledOpacity
    scale: root.hoverScaleEnabled && root.hovered ? root.hoverScale : 1

    Behavior on border.color {
        ColorAnimation {
            duration: Config.motion.duration.shortMs
            easing.type: Config.motion.easing.standard
        }
    }
    Behavior on color {
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
        antialiasing: true
        color: Config.m3.onSurface
        opacity: root.pressed ? Config.state.pressedOpacity : (root.hovered ? Config.state.hoverOpacity : 0)
        radius: root.radius
        visible: root.enabled
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true

        onClicked: root.clicked()
        onEntered: root.hovered = true
        onExited: {
            root.hovered = false;
            root.pressed = false;
        }
        onPressed: root.pressed = true
        onReleased: root.pressed = false
    }
}
