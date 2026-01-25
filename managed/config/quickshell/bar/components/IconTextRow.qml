import ".."
import QtQuick

Row {
    id: root

    property color iconColor: Config.color.on_surface
    property int iconPixelSize: Config.iconSize
    property string iconText: ""
    property string text: ""
    property color textColor: Config.color.on_surface
    property int textPixelSize: Config.fontSize

    spacing: Config.moduleSpacing

    IconLabel {
        color: root.iconColor
        font.pixelSize: root.iconPixelSize
        text: root.iconText
    }
    BarLabel {
        color: root.textColor
        font.pixelSize: root.textPixelSize
        text: root.text
    }
}
