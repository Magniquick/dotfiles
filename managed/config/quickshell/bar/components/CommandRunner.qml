import QtQml
import QtQuick
import Quickshell.Io
import "../../common" as Common

Item {
    id: root

    // String uses `sh -c` for backward-compat. Prefer passing an argv array.
    property var command: ""
    property bool enabled: true
    property int intervalMs: 10000
    property string output: ""
    property string errorOutput: ""
    property bool logErrors: false
    readonly property bool running: process.running
    property int timeoutMs: 0

    signal ran(string output)
    signal error(string errorOutput, int exitCode)
    signal timeout

    function trigger() {
        if (!enabled)
            return;
        if (!command)
            return;
        if (typeof command === "string" && command.trim() === "")
            return;
        if (Array.isArray(command) && command.length === 0)
            return;

        process.command = Common.ProcessHelper.normalize(command);
        process.running = true;

        if (root.timeoutMs > 0) {
            timeoutTimer.restart();
        }
    }

    visible: false

    Timer {
        interval: root.intervalMs
        repeat: true
        running: root.enabled && root.intervalMs > 0
        triggeredOnStart: true

        onTriggered: root.trigger()
    }
    Timer {
        id: timeoutTimer

        interval: root.timeoutMs
        repeat: false
        running: false

        onTriggered: {
            if (process.running) {
                if (root.logErrors) {
                    const cmdText = Array.isArray(root.command) ? root.command.join(" ") : String(root.command);
                    console.warn(`CommandRunner: Command '${cmdText}' timed out after ${root.timeoutMs}ms`);
                }
                process.running = false;
                root.timeout();
            }
        }
    }
    Process {
        id: process

        stdout: StdioCollector {
            id: stdoutCollector

            waitForEnd: true

            onStreamFinished: {
                root.output = stdoutCollector.text.trim();
                root.ran(root.output);
            }
        }

        stderr: StdioCollector {
            id: stderrCollector

            waitForEnd: true
        }
        // qmllint disable signal-handler-parameters
        onExited: code => {
            timeoutTimer.stop();
            root.errorOutput = stderrCollector.text.trim();

            if (code !== 0 || root.errorOutput !== "") {
                if (root.logErrors) {
                    console.error(`CommandRunner: Command '${root.command}' failed with exit code ${code}`);
                    if (root.errorOutput !== "")
                        console.error(`CommandRunner: stderr: ${root.errorOutput}`);
                }
                root.error(root.errorOutput, code);
            }
        }
        // qmllint enable signal-handler-parameters
    }
}
