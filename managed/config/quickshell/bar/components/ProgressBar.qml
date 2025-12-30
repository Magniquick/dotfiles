import ".."
import QtQuick

Item {
    id: root

    property int barHeight: 6
    property color fillColor: Config.m3.primary
    property color trackColor: Config.m3.surfaceVariant
    property real value: 0

    implicitHeight: root.barHeight
    implicitWidth: 180

    Rectangle {
        id: track

        anchors.fill: parent
        color: root.trackColor
        opacity: 0.9
        radius: root.barHeight / 2
    }
    Rectangle {
        id: fill

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: root.fillColor
        height: parent.height
        radius: track.radius
        width: Math.max(0, Math.min(1, root.value)) * parent.width
    }
}
