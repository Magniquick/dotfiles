import "../"
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

BarBlock {
    id: text

    property real percentFree

    Process {
        id: memProc

        command: ["sh", "-c", "free | grep Mem | awk '{print $3/$2 * 100.0}'"]
        running: true

        stdout: SplitParser {
            onRead: data => {
                return percentFree = data;
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: memProc.running = true
    }

    content: BarText {
        symbolText: `- ${Math.floor(percentFree)}%`
    }
}
