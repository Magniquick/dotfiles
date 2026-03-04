import ".."
import QtQuick

Text {
    color: Config.color.on_surface
    elide: Text.ElideRight
    renderType: Text.NativeRendering
    font.family: Config.iconFontFamily
    font.pixelSize: Config.iconSize
    maximumLineCount: 1
    verticalAlignment: Text.AlignVCenter
}
