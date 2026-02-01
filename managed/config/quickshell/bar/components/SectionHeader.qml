import QtQuick
import QtQuick.Layouts
import ".."

Text {
    id: root

    Layout.bottomMargin: Config.space.xs
    color: Config.color.primary
    font.family: Config.fontFamily
    font.letterSpacing: 1.5
    font.pixelSize: Config.type.labelSmall.size
    font.weight: Font.Black
}
