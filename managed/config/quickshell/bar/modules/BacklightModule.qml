import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Controls
import "./Label.qml"
import "../theme"

Item {
  id: root
  property real percent: 0
  property string icon: iconFor(percent)
  implicitHeight: label.implicitHeight
  implicitWidth: label.implicitWidth

  function iconFor(pct) {
    const icons = [
      "", "", "", "", "", "", "", "",
      "", "", "", "", "", "", "󰃚",
    ];
    const index = Math.min(icons.length - 1, Math.max(0, Math.round((pct / 100) * (icons.length - 1))));
    return icons[index];
  }

  Timer {
    id: pollTimer
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: readProc.running = true
  }

  Process {
    id: readProc
    command: [ "sh", "-c", "brillo -G 2>/dev/null || brightnessctl -m | cut -d',' -f4 | tr -d '%'" ]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        const pct = parseFloat(this.text.trim());
        if (!isNaN(pct)) {
          root.percent = pct;
          root.icon = iconFor(pct);
        }
      }
    }
  }

  Label {
    id: label
    text: icon
    color: Theme.colors.yellow
    ToolTip.visible: mouseArea.containsMouse
    ToolTip.text: `Brightness: ${percent.toFixed(0)}%`
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.AllButtons
    scrollGestureEnabled: true
    onWheel: wheel => {
      const delta = wheel.angleDelta.y;
      const cmd = delta > 0 ? "brillo -U 1" : "brillo -A 1";
      Quickshell.execDetached({ command: [ "sh", "-c", cmd ] });
      readProc.running = true;
    }
  }
}
