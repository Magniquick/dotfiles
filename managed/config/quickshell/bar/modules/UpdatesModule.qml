import QtQuick
import Quickshell.Io
import "./Label.qml"
import "../theme"

Item {
  id: root
  property string icon: ""
  property string text: ""
  property bool show: true
  property bool available: false
  visible: available && show
  implicitHeight: label.implicitHeight
  implicitWidth: label.implicitWidth

  Component.onCompleted: checkProc.running = true

  Process {
    id: checkProc
    running: false
    command: [ "sh", "-c", "command -v waybar-module-pacman-updates >/dev/null 2>&1 && echo ok || true" ]
    stdout: StdioCollector {
      onStreamFinished: {
        root.available = (this.text || "").indexOf("ok") !== -1;
        pollTimer.running = root.available;
        if (!root.available) {
          root.icon = "";
          root.text = "";
          root.show = false;
        }
      }
    }
  }

  Timer {
    id: pollTimer
    interval: 30000
    running: false
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (root.available)
        updatesProc.running = true;
    }
  }

  Process {
    id: updatesProc
    running: false
    command: [
      "waybar-module-pacman-updates",
      "--tooltip-align-columns",
      "--no-zero-output",
      "--interval-seconds", "30",
      "--network-interval-seconds", "300",
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const parsed = JSON.parse(this.text || "{}");
          root.icon = parsed.icon || "";
          root.text = parsed.text || "";
          root.show = !!root.text;
        } catch (e) {
          root.icon = "";
          root.text = "";
          root.show = false;
        }
      }
    }
  }

  Label {
    id: label
    visible: show
    text: `${icon} ${text}`.trim()
  }

  MouseArea {
    anchors.fill: parent
    visible: show
    onClicked: Quickshell.execDetached({
      command: [ "runapp", "kitty", "-o", "tab_bar_style=hidden", "--class", "yay", "-e", "yay", "-Syu" ],
    })
  }
}
