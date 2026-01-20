import QtQuick
import "../common" as Common

Item {
    id: root
    property var entry
    signal dismissRequested

    width: 320
    implicitHeight: content.implicitHeight + 20

    Rectangle {
        anchors.fill: parent
        color: Common.ColorPalette.palette.crust
        radius: 18
        border.width: 8
        border.color: Common.ColorPalette.palette.base
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.dismissRequested()
        cursorShape: Qt.PointingHandCursor
    }

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
        showCloseButton: false
    }
}
