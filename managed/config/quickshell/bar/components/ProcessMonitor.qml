/**
 * @component ProcessMonitor
 * @description A wrapper around Quickshell.Process that adds automatic crash recovery with exponential backoff.
 */
import QtQuick
import Quickshell.Io

Item {
    id: root

    property var command: [] // Command to run (string or array of strings)
    property bool enabled: true // Whether the process should be running
    property string processName: (Array.isArray(command) ? command[0] : command) || "Process"
    
    property int restartAttempts: 0
    property bool degraded: false
    
    // Configuration
    property int maxBackoffMs: 30000
    property int baseBackoffMs: 1000
    property int stabilityThresholdMs: 60000

    signal output(string data)
    signal error(string data)
    
    // Internal state
    property bool _waitingForRestart: false

    Timer {
        id: restartTimer
        interval: Math.min(root.maxBackoffMs, root.baseBackoffMs * Math.pow(2, root.restartAttempts))
        running: false
        onTriggered: {
             root.degraded = false;
             root._waitingForRestart = false;
        }
    }

    Timer {
        id: stabilityTimer
        interval: root.stabilityThresholdMs
        running: process.running
        repeat: false
        onTriggered: {
            if (root.restartAttempts > 0) {
                 console.log(root.processName + ": stable for " + (root.stabilityThresholdMs/1000) + "s, resetting backoff");
            }
            root.restartAttempts = 0;
        }
    }

    Process {
        id: process
        command: root.command
        running: root.enabled && !root._waitingForRestart

        stdout: SplitParser {
            onRead: data => root.output(data)
        }
        
        // Assuming stderr might also be useful, but original code didn't use it.
        // I'll leave stderr alone or expose it if needed. SystemdFailedModule used debug logging but from logic.
        
        // qmllint disable signal-handler-parameters
        onExited: code => {
            // Only handle crash if it was supposed to be running
            if (!root.enabled) return;

            if (root.restartAttempts === 0) {
                console.warn(`${root.processName}: exited with code ${code}, attempting restart`);
            } else {
                 const backoff = Math.min(root.maxBackoffMs, root.baseBackoffMs * Math.pow(2, root.restartAttempts));
                 console.warn(`${root.processName}: crashed again (attempt ${root.restartAttempts + 1}), next restart in ${backoff}ms`);
            }
            
            root.degraded = true;
            root.restartAttempts++;
            stabilityTimer.stop();
            
            root._waitingForRestart = true;
            restartTimer.restart();
        }
        // qmllint enable signal-handler-parameters
    }
}
