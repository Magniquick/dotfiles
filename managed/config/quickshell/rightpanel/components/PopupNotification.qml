import QtQuick

Item {
    id: root
    property var entry
    signal dismissRequested

    width: 320
    implicitHeight: frame.implicitHeight
    // ListView positions delegates using `height`; bind it so late implicitHeight
    // changes (e.g. async image checks / text wrap) trigger relayout instead of
    // overlapping the previous item.
    height: implicitHeight

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
