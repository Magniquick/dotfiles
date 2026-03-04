import QtQuick
import QtQuick.Layouts
import ".."

RowLayout {
    id: root

    property alias text: label.text

    Layout.fillWidth: true
    Layout.bottomMargin: Config.space.xs
    spacing: Config.space.sm

    Text {
        id: label

        color: Config.color.primary
        font.family: Config.fontFamily
        font.letterSpacing: 1.5
        font.pixelSize: Config.type.labelSmall.size
        font.weight: Font.Black
    }
    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        Layout.fillWidth: true
        color: Qt.alpha(Config.color.outline_variant, 0.55)
        implicitHeight: 1
        radius: 1
    }
}
