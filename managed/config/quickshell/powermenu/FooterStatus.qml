import QtQuick

Column {
    id: footer

    property var colors
    property string hoverAction: ""
    property string selection: ""

    spacing: 10

    Text {
        color: footer.colors.on_surface_variant
        font.bold: true
        font.family: "monospace"
        font.pointSize: 17
        text: "/ Pl5y1ng GØd /"
    }
    Row {
        spacing: 8

        Text {
            color: footer.colors.on_surface_variant
            font.bold: true
            font.family: "monospace"
            font.pointSize: 17
            text: ""
        }
        Text {
            color: footer.colors.on_surface_variant
            font.bold: true
            font.family: "monospace"
            font.pointSize: 17
            text: footer.selection !== "" ? footer.selection : footer.hoverAction
        }
        Text {
            id: cursor

            color: footer.colors.on_surface
            font.bold: true
            font.family: "monospace"
            font.pointSize: 17
            text: "_"
        }
    }
}
