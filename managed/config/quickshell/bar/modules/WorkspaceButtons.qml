import QtQuick
import Quickshell.Hyprland
import "./Label.qml"
import "../theme"

Row {
  id: root
  property bool special: false
  spacing: 0

  Repeater {
    model: Hyprland.workspaces.values.filter(ws => special ? ws.name.startsWith("special") || ws.id < 0 : !(ws.name && ws.name.startsWith("special")) && ws.id >= 0)

    delegate: Rectangle {
      required property var modelData
      readonly property bool active: modelData.active
      readonly property bool urgent: modelData.urgent
      readonly property string displayLabel: special ? specialLabel(modelData) : defaultLabel(modelData)

      color: active ? Theme.colors.surface1 : "transparent"
      radius: Theme.radius
      border.width: 0
      anchors.verticalCenter: parent ? parent.verticalCenter : undefined
      implicitHeight: Theme.barHeight
      implicitWidth: label.implicitWidth + Theme.modulePadX * 2

      function specialLabel(ws) {
        const name = ws.name || "";
        if (name.indexOf("magic") !== -1) return "";
        if (name.indexOf("spotify") !== -1) return "";
        if (name.indexOf("whatsapp") !== -1) return "󰖣";
        return "";
      }

      function defaultLabel(ws) {
        if (ws.name && !isNaN(parseInt(ws.name, 10)))
          return ws.name;
        return `${ws.id}`;
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: modelData.activate()
        cursorShape: Qt.PointingHandCursor
        onEntered: parent.color = Theme.colors.surface0
        onExited: parent.color = parent.active ? Theme.colors.surface1 : "transparent"
        onReleased: parent.color = parent.active ? Theme.colors.surface1 : "transparent"
      }

      Label {
        id: label
        anchors.centerIn: parent
        text: displayLabel
        color: active ? Theme.colors.mauve : Theme.colors.subtext0
      }
    }
  }
}
