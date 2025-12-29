import QtQuick

Item {
    id: bunnyBlock

    property string bunnyHead: bunnyHeads.default
    readonly property var bunnyHeads: ({
            "default": "( . .) ",
            "headpat": "( ^ ^) "
        })
    property var colors
    property int headpatResetDelay: 200
    property bool headpatting: bunnyHead === bunnyHeads.headpat

    height: implicitHeight
    implicitHeight: bunnyText.implicitHeight + 12
    implicitWidth: bunnyText.implicitWidth
    width: bunnyText.implicitWidth

    Column {
        id: bunnyText

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        spacing: 6

        Text {
            id: bunnyLine1

            color: colors.text
            font.bold: true
            font.family: "monospace"
            font.pointSize: 17
            text: "(\\ /)"
        }
        Text {
            id: bunnyLine2

            color: colors.text
            font.bold: true
            font.family: "monospace"
            font.pointSize: 17
            text: bunnyHead
        }
        Text {
            id: bunnyLine3

            color: colors.text
            font.bold: true
            font.family: "monospace"
            font.pointSize: 17
            text: qsTr("c(<font color='%1'>\"</font>)(<font color='%1'>\"</font>)").arg(colors.red)
            textFormat: Text.RichText
        }
    }
    Timer {
        id: headpatResetTimer

        interval: headpatResetDelay
        repeat: false
        running: false

        onTriggered: bunnyHead = bunnyHeads.default
    }
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        propagateComposedEvents: false

        onEntered: {
            headpatResetTimer.stop();
            bunnyHead = bunnyHeads.headpat;
        }
        onExited: {
            headpatResetTimer.stop();
            headpatResetTimer.start();
        }
    }
}
