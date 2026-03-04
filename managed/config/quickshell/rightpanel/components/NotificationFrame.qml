import QtQuick
import Qcm.Material as MD
import "../../common" as Common

Item {
    id: root
    signal clicked

    property int paddingLeft: 22
    property int paddingRight: 22
    property int paddingTop: 18
    property int paddingBottom: 18
    property int frameRadius: 18
    // Hairline outline. The old thick border made cards feel flat.
    property int frameBorderWidth: 1
    property color frameColor: Common.Config.color.surface
    // Strict parity with bar module borders.
    property color frameBorderColor: Qt.alpha(Common.Config.color.outline_variant, 0.6)
    // Conventional "card" depth. Tuned by callers (list vs popup).
    property int elevation: MD.Token.elevation.level1

    default property alias contentData: contentHost.data

    implicitHeight: contentHost.implicitHeight + paddingTop + paddingBottom

    MD.ElevationRectangle {
        anchors.fill: parent
        color: root.frameColor
        corners: MD.Util.corners(root.frameRadius)
        elevation: root.elevation
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: root.frameRadius
        border.width: root.frameBorderWidth
        border.color: root.frameBorderColor
    }

    Rectangle {
        anchors.fill: parent
        clip: true
        color: "transparent"
        radius: root.frameRadius

        HybridRipple {
            anchors.fill: parent
            color: Common.Config.color.on_surface
            pressX: frameMouseArea.pressX
            pressY: frameMouseArea.pressY
            pressed: frameMouseArea.pressed
            radius: root.frameRadius
            stateOpacity: frameMouseArea.containsMouse ? Common.Config.state.hoverOpacity : 0
        }
    }
    MouseArea {
        id: frameMouseArea
        property real pressX: width / 2
        property real pressY: height / 2
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
        cursorShape: Qt.PointingHandCursor
        onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
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
