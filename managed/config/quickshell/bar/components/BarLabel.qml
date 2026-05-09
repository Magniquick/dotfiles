import ".."
import QtQuick

Text {
    color: Config.color.on_surface
    elide: Text.ElideRight
    renderType: Text.NativeRendering
    font.family: Config.fontFamily
    font.pixelSize: Config.type.bodyMedium.size
    font.weight: Font.Medium
    maximumLineCount: 1
    verticalAlignment: Text.AlignVCenter
}
