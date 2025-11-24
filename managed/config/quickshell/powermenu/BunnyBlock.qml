import QtQuick

Item {
  id: bunnyBlock
  property var colors
  property int headpatResetDelay: 200
  readonly property var bunnyHeads: ({
    "default": "( . .) ",
    "headpat": "( ^ ^) "
  })
  property string bunnyHead: bunnyHeads.default
  property bool headpatting: bunnyHead === bunnyHeads.headpat

  width: bunnyText.implicitWidth
  implicitWidth: bunnyText.implicitWidth
  implicitHeight: bunnyText.implicitHeight + 12
  height: implicitHeight

  Column {
    id: bunnyText
    spacing: 6
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter

    Text {
      id: bunnyLine1
      text: "(\\ /)"
      color: colors.text
      font.family: "monospace"
      font.pointSize: 17
      font.bold: true
    }
    Text {
      id: bunnyLine2
      text: bunnyHead
      color: colors.text
      font.family: "monospace"
      font.pointSize: 17
      font.bold: true
    }
    Text {
      id: bunnyLine3
      color: colors.text
      font.family: "monospace"
      font.pointSize: 17
      font.bold: true
      textFormat: Text.RichText
      text: qsTr("c(<font color='%1'>\"</font>)(<font color='%1'>\"</font>)").arg(colors.red)
    }
  }

  Timer {
    id: headpatResetTimer
    interval: headpatResetDelay
    running: false
    repeat: false
    onTriggered: bunnyHead = bunnyHeads.default
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    propagateComposedEvents: false
    onEntered: {
      headpatResetTimer.stop()
      bunnyHead = bunnyHeads.headpat
    }
    onExited: {
      headpatResetTimer.stop()
      headpatResetTimer.start()
    }
  }
}
