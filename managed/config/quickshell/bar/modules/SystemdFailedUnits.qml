import QtQuick
import Quickshell.Io
import "./Label.qml"
import "../theme"

Item {
  id: root
  property int failedCount: 0
  implicitHeight: label.implicitHeight
  implicitWidth: label.implicitWidth

  Timer {
    id: pollTimer
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: checkProc.running = true
  }

  Process {
    id: checkProc
    running: false
    command: [ "sh", "-c", "systemctl --failed --no-legend | grep -c \"\" || true" ]
    stdout: StdioCollector {
      onStreamFinished: {
        const count = parseInt(this.text.trim(), 10);
        root.failedCount = isNaN(count) ? 0 : count;
      }
    }
  }

  Label {
    id: label
    text: ` ${failedCount} units failed`
    color: Theme.colors.red
  }
}
