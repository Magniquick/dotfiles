import ".."
import QtQuick

Text {
    color: Config.textColor
    elide: Text.ElideRight
    font.family: Config.iconFontFamily
    font.pixelSize: Config.iconSize
    maximumLineCount: 1
    verticalAlignment: Text.AlignVCenter
}
