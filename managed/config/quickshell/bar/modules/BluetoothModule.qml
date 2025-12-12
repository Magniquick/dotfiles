import QtQuick
import QtQuick.Controls
import QtQml
import Quickshell
import "./Label.qml"
import "../theme"

Item {
  id: root
  property var bluetooth: null
  property string icon: "󰂲"
  property string text: ""
  property bool available: false
  property int connectedCount: 0
  property string tooltipText: "Bluetooth off"
  implicitHeight: label.implicitHeight
  implicitWidth: label.implicitWidth
  visible: available

  function createBluetooth() {
    const src = "import Quickshell.Bluetooth; Bluetooth {}";
    const comp = Qt.createComponent(src);
    if (comp.status === Component.Ready) {
      bluetooth = comp.createObject(root);
      available = !!bluetooth;
    } else {
      comp.statusChanged.connect(function(status) {
        if (status === Component.Ready) {
          bluetooth = comp.createObject(root);
          available = !!bluetooth;
        }
      });
    }
  }

  function updateDisplay() {
    if (!available || !bluetooth) {
      icon = "󰂲";
      text = "";
      connectedCount = 0;
      tooltipText = "Bluetooth unavailable";
      return;
    }
    const adapter = bluetooth.defaultAdapter;
    const devices = bluetooth.devices && bluetooth.devices.values ? bluetooth.devices.values : [];
    if (!adapter || !adapter.enabled) {
      icon = "󰂲";
      text = "";
      connectedCount = 0;
      tooltipText = "Bluetooth off";
      return;
    }

    const connected = devices.filter(d => d.connected);
    connectedCount = connected.length;
    if (connectedCount === 0) {
      icon = "󰂲";
      text = "";
      tooltipText = "0 devices connected";
      return;
    }

    const device = connected[0];
    const name = device.name || device.deviceName || device.alias || "Device";
    const battery = device.batteryAvailable ? ` ${Math.round(device.battery * 100)}%` : "";
    icon = ` ${name}${battery}`;
    text = icon;

    const details = connected.map(d => {
      const alias = d.name || d.deviceName || d.alias || "Device";
      const addr = d.address || "";
      const batt = d.batteryAvailable ? `${Math.round(d.battery * 100)}%` : "";
      const battLine = batt ? `\n\n${batt}` : "";
      return `${alias}\n${addr}${battLine}`;
    });
    tooltipText = `${connectedCount} devices connected${details.length ? "\n\n" + details.join("\n\n") : ""}`;
  }

  Component.onCompleted: createBluetooth()

  Connections {
    target: bluetooth
    function onDevicesChanged() { updateDisplay(); }
    function onDefaultAdapterChanged() { updateDisplay(); }
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: updateDisplay()
  }

  Label {
    id: label
    text: root.text || root.icon
    color: Theme.colors.text
    ToolTip.visible: mouseArea.containsMouse
    ToolTip.text: tooltipText
  }

  MouseArea {
    anchors.fill: parent
    id: mouseArea
    hoverEnabled: true
    onClicked: Quickshell.execDetached({
      command: [ "runapp", "kitty", "-o", "tab_bar_style=hidden", "--class", "bluetui", "-e", "bluetui" ],
    })
  }
}
