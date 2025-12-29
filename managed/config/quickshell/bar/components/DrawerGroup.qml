import ".."
import QtQuick

Item {
    id: root

    property alias alwaysContent: alwaysRow.data
    property alias drawerContent: drawerRow.data
    property bool drawerLeft: false
    property int duration: Config.motion.duration.medium
    property bool open: false
    property bool openOnHover: true
    property real reveal: root.open ? 1 : 0
    property int spacing: Config.groupModuleSpacing

    implicitHeight: alwaysRow.implicitHeight
    implicitWidth: alwaysRow.implicitWidth + drawerContainer.width

    Behavior on reveal {
        NumberAnimation {
            duration: root.duration
            easing.type: Config.motion.easing.standard
        }
    }

    Row {
        id: groupRow

        anchors.fill: parent
        layoutDirection: root.drawerLeft ? Qt.RightToLeft : Qt.LeftToRight
        spacing: root.spacing

        Row {
            id: alwaysRow

            spacing: root.spacing
        }
        Item {
            id: drawerContainer

            clip: true
            height: alwaysRow.implicitHeight
            implicitHeight: alwaysRow.implicitHeight
            implicitWidth: drawerRow.implicitWidth
            width: root.open ? drawerRow.implicitWidth : 0

            Behavior on width {
                NumberAnimation {
                    duration: root.duration
                    easing.type: Config.motion.easing.standard
                }
            }

            Row {
                id: drawerRow

                anchors.verticalCenter: parent.verticalCenter
                opacity: root.reveal
                scale: 0.98 + (0.02 * root.reveal)
                spacing: root.spacing
                x: root.drawerLeft ? Math.round((1 - root.reveal) * -Config.motion.distance.medium) : Math.round((1 - root.reveal) * Config.motion.distance.medium)
            }
        }
    }
    HoverHandler {
        onHoveredChanged: {
            if (root.openOnHover)
                root.open = hovered;
        }
    }
}
