pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    property string time
    property string date

    Process {
        id: dateProc

        command: ["date", "+%a %e %b|%R"]
        running: true

        stdout: SplitParser {
            onRead: data => {
                date = data.split("|")[0];
                time = data.split("|")[1];
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: dateProc.running = true
    }
}
