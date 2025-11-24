import QtQuick

Column {
  id: footer
  property var colors
  property string selection: ""
  property string hoverAction: ""

  spacing: 10

  Text {
    text: "/ Pl5y1ng GØd /"
    font.family: "monospace"
    font.pointSize: 17
    font.bold: true
    color: colors.subtext0
  }
  Row {
    spacing: 8
    Text {
      text: ""
      font.family: "monospace"
      font.pointSize: 17
      font.bold: true
      color: colors.subtext0
    }
    Text {
      text: selection !== "" ? selection : hoverAction
      font.family: "monospace"
      font.pointSize: 17
      font.bold: true
      color: colors.subtext0
    }
    Text {
      id: cursor
      text: "_"
      font.family: "monospace"
      font.pointSize: 17
      font.bold: true
      color: colors.text
      SequentialAnimation on opacity {
        running: true
        loops: Animation.Infinite
        NumberAnimation { from: 1; to: 0; duration: 500 }
        NumberAnimation { from: 0; to: 1; duration: 500 }
      }
    }
  }
}
