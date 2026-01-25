import QtQuick
import "../common" as Common

Item {
    id: root
    signal clicked

    property int paddingLeft: 22
    property int paddingRight: 22
    property int paddingTop: 18
    property int paddingBottom: 18
    property int frameRadius: 18
    property int frameBorderWidth: 8
    property color frameColor: Common.Config.color.surface
    property color frameBorderColor: Common.Config.color.surface_container

    default property alias contentData: contentHost.data

    implicitHeight: contentHost.implicitHeight + paddingTop + paddingBottom

    Rectangle {
        anchors.fill: parent
        color: root.frameColor
        radius: root.frameRadius
        border.width: root.frameBorderWidth
        border.color: root.frameBorderColor
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
        cursorShape: Qt.PointingHandCursor
    }

    Item {
        id: contentHost
        implicitHeight: childrenRect.height
        height: implicitHeight
        width: parent.width - root.paddingLeft - root.paddingRight
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: root.paddingLeft
            rightMargin: root.paddingRight
            topMargin: root.paddingTop
        }
    }
}
