import QtQuick
import Qcm.Material as MD
import "../../common" as Common

Rectangle {
    id: root

    property string label: ""
    property string icon: ""
    signal clicked

    radius: Common.Config.shape.corner.sm
    color: Common.Config.color.surface_variant
    implicitHeight: Common.Config.space.xl
    implicitWidth: contentRow.implicitWidth + Common.Config.space.md * 2

    Behavior on color {
        ColorAnimation {
            duration: Common.Config.motion.duration.shortMs
            easing.type: Common.Config.motion.easing.standard
        }
    }

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: Common.Config.space.xs

        Text {
            visible: root.icon.length > 0
            text: root.icon
            color: Common.Config.color.on_surface
            font.family: Common.Config.iconFontFamily
            font.pixelSize: Common.Config.type.labelMedium.size
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: root.label
            color: Common.Config.color.on_surface
            font.family: Common.Config.fontFamily
            font.pixelSize: Common.Config.type.labelMedium.size
            font.weight: Common.Config.type.labelMedium.weight
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    HybridRipple {
        anchors.fill: parent
        color: Common.Config.color.on_surface
        pressX: actionArea.pressX
        pressY: actionArea.pressY
        pressed: actionArea.pressed
        radius: parent.radius
        stateOpacity: actionArea.containsMouse ? Common.Config.state.hoverOpacity : 0
    }
    MouseArea {
        id: actionArea
        property real pressX: width / 2
        property real pressY: height / 2
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
        onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
    }
}
