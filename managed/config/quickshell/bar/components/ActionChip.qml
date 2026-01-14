import ".."
import QtQuick

ActionButtonBase {
    id: root

    property bool loading: false
    property string text: ""

    hoverScaleEnabled: true
    implicitHeight: Config.space.xl + Config.space.xs
    implicitWidth: label.implicitWidth + Config.space.xl + (root.loading ? spinner.width + Config.space.sm : 0)
    radius: height / 2

    onClicked: {
        flashAnimation.restart();
    }

    Item {
        anchors.centerIn: parent
        implicitHeight: Math.max(label.implicitHeight, spinner.height)
        implicitWidth: label.implicitWidth + (root.loading ? spinner.width + Config.space.sm : 0)

        Text {
            id: spinner

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: root.active ? Config.m3.onSurface : Config.m3.onSurfaceVariant
            font.family: Config.iconFontFamily
            font.pixelSize: Config.type.labelMedium.size
            opacity: root.loading ? 1 : 0
            text: "󰔟"
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Config.motion.duration.shortMs
                    easing.type: Config.motion.easing.standard
                }
            }

            RotationAnimator on rotation {
                duration: 1000
                from: 0
                loops: Animation.Infinite
                running: root.loading && root.enabled
                to: 360
            }
        }

        Text {
            id: label

            anchors.left: root.loading ? spinner.right : parent.left
            anchors.leftMargin: root.loading ? Config.space.sm : 0
            anchors.verticalCenter: parent.verticalCenter
            color: root.active ? Config.m3.onSurface : Config.m3.onSurfaceVariant
            font.family: Config.fontFamily
            font.pixelSize: Config.type.labelMedium.size
            font.weight: Config.type.labelMedium.weight
            text: root.text
        }
    }

    Rectangle {
        id: flash

        anchors.fill: parent
        antialiasing: true
        color: root.active ? Config.m3.onPrimary : Config.m3.primary
        opacity: 0
        radius: root.radius

        SequentialAnimation {
            id: flashAnimation

            NumberAnimation {
                duration: Config.motion.duration.shortMs
                easing.type: Config.motion.easing.emphasized
                property: "opacity"
                target: flash
                to: 0.3
            }
            NumberAnimation {
                duration: Config.motion.duration.medium
                easing.type: Config.motion.easing.standard
                property: "opacity"
                target: flash
                to: 0
            }
        }
    }
}
