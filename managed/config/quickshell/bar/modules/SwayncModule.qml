import QtQuick
import Quickshell
import Quickshell.Io
import "./Label.qml"
import "../theme"

Item {
  id: root
  property string stateClass: "none"
  property string icon: iconFor(stateClass)
  implicitHeight: label.implicitHeight
  implicitWidth: label.implicitWidth

  readonly property var iconMap: ({
    "notification": "󱅫",
    "none": "",
    "dnd-notification": "󰂠",
    "dnd-none": "󰪓",
    "inhibited-notification": "󰂛",
    "inhibited-none": "󰪑",
    "dnd-inhibited-notification": "󰂛",
    "dnd-inhibited-none": "󰪑",
  })

  function iconFor(state) {
    return iconMap[state] || iconMap["none"];
  }

  Process {
    id: swayncProc
    command: [ "swaync-client", "-swb" ]
    running: true
    stdout: SplitParser {
      onRead: data => {
        try {
          const parsed = JSON.parse(data || "{}");
          if (parsed.class) {
            stateClass = parsed.class;
            icon = iconFor(stateClass);
          }
        } catch (e) {
          // ignore
        }
      }
    }
  }

  Label {
    id: label
    text: `<span style=\"font-size:16pt\">${icon}</span>`
    textFormat: Text.RichText
    color: Theme.colors.text
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: (event) => {
      if (event.button === Qt.RightButton) {
        Quickshell.execDetached({ command: [ "swaync-client", "-d", "-sw" ] });
      } else {
        Quickshell.execDetached({ command: [ "swaync-client", "-t", "-sw" ] });
      }
    }
  }
}
