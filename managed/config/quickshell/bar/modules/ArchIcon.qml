import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Controls
import "./Label.qml"
import "../theme"

Item {
  id: root
  property string text: ""
  property string tooltip: ""

  implicitHeight: label.implicitHeight
  implicitWidth: label.implicitWidth

  Timer {
    id: pollTimer
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: archProc.running = true
  }

  Process {
    id: archProc
    running: false
    command: [ "sh", "-c", "~/.config/waybar/scripts/status.sh" ]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const parsed = JSON.parse(this.text || "{}");
          if (parsed.text)
            root.text = parsed.text;
          if (parsed.tooltip)
            root.tooltip = parsed.tooltip;
        } catch (e) {
          root.text = "";
          root.tooltip = "";
        }
      }
    }
  }

  MouseArea {
    id: archMouse
    anchors.fill: parent
    onClicked: Quickshell.execDetached({
      command: [ "quickshell", "-c", "powermenu", "ipc", "call", "powermenu", "toggle" ],
    })
    hoverEnabled: true
  }

  Label {
    id: label
    text: root.text
    color: Theme.colors.lavender
    ToolTip.visible: archMouse.containsMouse
    ToolTip.text: root.tooltip
  }
}
