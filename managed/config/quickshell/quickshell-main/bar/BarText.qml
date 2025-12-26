import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

Text {
    property string mainFont: "FiraCode"
    property string symbolFont: "Symbols Nerd Font Mono"
    property int pointSize: 12
    property int symbolSize: pointSize * 1.4
    property string symbolText
    property bool dim

    function wrapSymbols(text) {
        // Private Use Area
        // Supplementary Private Use Area-A
        // ? c

        if (!text)
            return "";

        const isSymbol = codePoint => {
            return (codePoint >= 57344 && codePoint <= 63743) || (codePoint >= 983040 && codePoint <= 1.04858e+06) || (codePoint >= 1.04858e+06 && codePoint <= 1.11411e+06);
        }; // Supplementary Private Use Area-B
        return text.replace(/./ug, c => {
            return isSymbol(c.codePointAt(0)) ? `<span style='font-family: ${symbolFont}; letter-spacing: 5px; font-size: ${symbolSize}px'>${c}</span>` : c;
        });
    }

    text: wrapSymbols(symbolText)
    anchors.centerIn: parent
    color: dim ? "#CCCCCC" : "white"
    textFormat: Text.RichText

    font {
        family: mainFont
        pointSize: pointSize
    }

    Text {
        id: textcopy

        visible: false
        text: parent.text
        textFormat: parent.textFormat
        color: parent.color
        font: parent.font
    }

    DropShadow {
        anchors.fill: parent
        horizontalOffset: 1
        verticalOffset: 1
        color: "#000000"
        source: textcopy
    }
}
