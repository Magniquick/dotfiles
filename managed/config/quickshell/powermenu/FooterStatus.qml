import QtQuick

Column {
    id: footer

    property var colors
    property string hoverAction: ""
    property string selection: ""

    spacing: 10

    Text {
        color: footer.colors.subtext0
        font.bold: true
        font.family: "monospace"
        font.pointSize: 17
        text: "/ Pl5y1ng GØd /"
    }
    Row {
        spacing: 8

        Text {
            color: footer.colors.subtext0
            font.bold: true
            font.family: "monospace"
            font.pointSize: 17
            text: ""
        }
        Text {
            color: footer.colors.subtext0
            font.bold: true
            font.family: "monospace"
            font.pointSize: 17
            text: footer.selection !== "" ? footer.selection : footer.hoverAction
        }
        Text {
            id: cursor

            color: footer.colors.text
            font.bold: true
            font.family: "monospace"
            font.pointSize: 17
            text: "_"

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: footer.visible

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
