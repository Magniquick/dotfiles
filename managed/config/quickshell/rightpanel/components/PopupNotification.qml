import QtQuick

Item {
    id: root
    property var entry
    signal dismissRequested

    width: 320
    implicitHeight: frame.implicitHeight

    NotificationFrame {
        id: frame
        anchors {
            left: parent.left
            right: parent.right
        }
        onClicked: root.dismissRequested()

        NotificationContent {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            entry: root.entry
            showCloseButton: false
        }
    }
}
