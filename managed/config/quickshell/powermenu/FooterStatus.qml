import QtQuick
import Quickshell

Column {
    id: footer

    property var colors
    property string hoverAction: ""
    property string selection: ""

    spacing: 10

    Text {
        color: colors.subtext0
        font.bold: true
        font.family: "monospace"
        font.pointSize: 17
        text: "/ Pl5y1ng GØd /"
    }
    Row {
        spacing: 8

        Text {
            color: colors.subtext0
            font.bold: true
            font.family: "monospace"
            font.pointSize: 17
            text: ""
        }
        Text {
            color: colors.subtext0
            font.bold: true
            font.family: "monospace"
            font.pointSize: 17
            text: selection !== "" ? selection : hoverAction
        }
        Text {
            id: cursor

            color: colors.text
            font.bold: true
            font.family: "monospace"
            font.pointSize: 17
            text: "_"

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: footer.QsWindow.window && footer.QsWindow.window.visible

                NumberAnimation {
                    duration: 500
                    from: 1
                    to: 0
                }
                NumberAnimation {
                    duration: 500
                    from: 0
                    to: 1
                }
            }
        }
    }
}
