import QtQuick
import "../common" as Common

Rectangle {
    id: root
    property string icon: ""
    property bool activated: false
    property bool enabled: true

    signal clicked()

    width: 24
    height: 24
    radius: 6
    color: activated ? Qt.alpha(Common.Config.color.primary, 0.25) :
           mouseArea.containsMouse ? Qt.alpha(Common.Config.color.on_surface, 0.1) : "transparent"

    opacity: enabled ? 1 : 0.35
    scale: mouseArea.pressed ? 0.92 : 1

    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }

    Text {
        anchors.centerIn: parent
        text: root.icon
        color: root.activated ? Common.Config.color.primary :
               mouseArea.containsMouse ? Common.Config.color.on_surface : Common.Config.color.on_surface_variant
        font.family: Common.Config.iconFontFamily
        font.pixelSize: 13
        opacity: root.activated ? 1 : 0.85

        Behavior on color { ColorAnimation { duration: 120 } }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.enabled) root.clicked()
    }
}
