import ".."
import QtQuick

Text {
    color: Config.m3.onSurface
    elide: Text.ElideRight
    font.family: Config.fontFamily
    font.pixelSize: Config.type.bodyMedium.size
    font.weight: Config.type.bodyMedium.weight
    maximumLineCount: 1
    verticalAlignment: Text.AlignVCenter
}
