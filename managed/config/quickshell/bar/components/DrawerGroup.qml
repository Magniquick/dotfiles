import ".."
import QtQuick

Item {
    id: root

    property alias alwaysContent: alwaysRow.data
    property alias drawerContent: drawerRow.data
    property bool open: false
    property bool openOnHover: true
    property bool drawerLeft: false
    property int duration: Config.motion.duration.medium
    property int spacing: Config.groupModuleSpacing
    property real reveal: root.open ? 1 : 0

    implicitWidth: alwaysRow.implicitWidth + drawerContainer.width
    implicitHeight: alwaysRow.implicitHeight

    Row {
        id: groupRow

        anchors.fill: parent
        spacing: root.spacing
        layoutDirection: root.drawerLeft ? Qt.RightToLeft : Qt.LeftToRight

        Row {
            id: alwaysRow

            spacing: root.spacing
        }

        Item {
            id: drawerContainer

            clip: true
            width: root.open ? drawerRow.implicitWidth : 0
            height: alwaysRow.implicitHeight
            implicitWidth: drawerRow.implicitWidth
            implicitHeight: alwaysRow.implicitHeight

            Row {
                id: drawerRow

                anchors.verticalCenter: parent.verticalCenter
                spacing: root.spacing
                opacity: root.reveal
                scale: 0.98 + (0.02 * root.reveal)
                x: root.drawerLeft ? Math.round((1 - root.reveal) * -Config.motion.distance.medium) : Math.round((1 - root.reveal) * Config.motion.distance.medium)
            }

            Behavior on width {
                NumberAnimation {
                    duration: root.duration
                    easing.type: Config.motion.easing.standard
                }
            }
        }
    }

    HoverHandler {
        onHoveredChanged: {
            if (root.openOnHover)
                root.open = hovered;
        }
    }

    Behavior on reveal {
        NumberAnimation {
            duration: root.duration
            easing.type: Config.motion.easing.standard
        }
    }
}
