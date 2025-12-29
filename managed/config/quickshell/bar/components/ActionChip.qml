import ".."
import QtQuick

ActionButtonBase {
    id: root

    property string text: ""

    hoverScaleEnabled: true
    implicitHeight: Config.space.xl + Config.space.xs
    implicitWidth: label.implicitWidth + Config.space.xl
    radius: height / 2

    Text {
        id: label

        anchors.centerIn: parent
        color: root.active ? Config.textColor : Config.textMuted
        font.family: Config.fontFamily
        font.pixelSize: Config.type.labelMedium.size
        font.weight: Config.type.labelMedium.weight
        text: root.text
    }
}
