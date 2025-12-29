import QtQml
import QtQuick
import Quickshell.Io

Item {
    id: root

    property string command: ""
    property bool enabled: true
    property int intervalMs: 10000
    property string output: ""
    readonly property bool running: process.running

    signal ran(string output)

    function trigger() {
        if (!enabled || !command)
            return;

        process.command = ["sh", "-c", command];
        process.running = true;
    }

    visible: false

    Component.onCompleted: trigger()

    Timer {
        interval: root.intervalMs
        repeat: true
        running: root.enabled && root.intervalMs > 0

        onTriggered: root.trigger()
    }
    Process {
        id: process

        stdout: StdioCollector {
            id: collector

            waitForEnd: true

            onStreamFinished: {
                root.output = collector.text.trim();
                root.ran(root.output);
            }
        }
    }
}
