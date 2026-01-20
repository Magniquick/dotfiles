import QtQuick
import "../common" as Common

Item {
    id: root
    property var entry
    signal dismissRequested

    width: 400
    implicitHeight: card.implicitHeight

    Rectangle {
        id: card
        anchors {
            left: parent.left
            right: parent.right
        }
        color: Common.ColorPalette.palette.crust
        radius: 18
        border.width: 8
        border.color: Common.ColorPalette.palette.base
        implicitHeight: content.implicitHeight + 20

        NotificationContent {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: 22
                rightMargin: 22
                topMargin: 10
            }
            entry: root.entry
            showCloseButton: true
            onCloseClicked: root.dismissRequested()
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: Common.Config.motion.duration.shortMs
            easing.type: Common.Config.motion.easing.standard
        }
    }
}
