import QtQuick
import "../../common" as Common

Item {
    id: root
    property var entry
    signal dismissRequested

    width: 400
    implicitHeight: frame.implicitHeight
    // Keep ListView layout stable when content height resolves after creation.
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
            showCloseButton: true
            showSourceButton: true
            showBodyLeadIcon: false
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
