import QtQuick
import "../common" as Common

Rectangle {
    id: root

    property string label: ""
    property string icon: ""
    signal clicked

    radius: Common.Config.shape.corner.sm
    color: actionArea.pressed ? Qt.alpha(Common.ColorPalette.palette.overlay2, 0.35) : actionArea.containsMouse ? Qt.alpha(Common.ColorPalette.palette.overlay2, 0.25) : Common.Config.surfaceVariant
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
            color: Common.Config.textColor
            font.family: Common.Config.iconFontFamily
            font.pixelSize: Common.Config.type.labelMedium.size
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: root.label
            color: Common.Config.textColor
            font.family: Common.Config.fontFamily
            font.pixelSize: Common.Config.type.labelMedium.size
            font.weight: Common.Config.type.labelMedium.weight
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: actionArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
