import QtQuick
import QtQml
import "./Label.qml"
import "../theme"

Item {
  id: root
  property var upower: null
  property bool available: false
  property real percent: 0
  property string icon: ""
  property string timeText: ""
  property string display: ""
  property bool showTime: false
  implicitHeight: label.implicitHeight
  implicitWidth: label.implicitWidth
  visible: available

  function createUpower() {
    const src = "import Quickshell.Services.UPower; UPower {}";
    const comp = Qt.createComponent(src);
    if (comp.status === Component.Ready) {
      upower = comp.createObject(root);
      available = !!upower;
    } else {
      comp.statusChanged.connect(function(status) {
        if (status === Component.Ready) {
          upower = comp.createObject(root);
          available = !!upower;
        }
      });
    }
  }

  function formatTime(seconds) {
    if (!seconds || seconds <= 0)
      return "";
    const hrs = Math.floor(seconds / 3600);
    const mins = Math.floor((seconds % 3600) / 60);
    return `${hrs}h ${mins}m`;
  }

  function stateString(state) {
    if (state === null || state === undefined)
      return "";
    const str = state.toString();
    if (str.indexOf("Charging") !== -1) return "Charging";
    if (str.indexOf("Discharging") !== -1 || str.indexOf("PendingDischarge") !== -1) return "Discharging";
    if (typeof state === "number") {
      if (state === 1) return "Charging";
      if (state === 2 || state === 6) return "Discharging";
    }
    return str;
  }

  function batteryIcon(pct, state) {
    const icons = [
      "󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾",
      "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"
    ];
    const clamped = Math.min(100, Math.max(0, pct));
    const idx = Math.round((clamped / 100) * (icons.length - 1));
    if (state === "Charging")
      return "󰂄";
    return icons[idx];
  }

  function updateBattery() {
    if (!available || !upower) {
      percent = 0;
      display = "";
      timeText = "";
      icon = "";
      return;
    }
    const device = upower.displayDevice;
    if (!device || !device.ready) {
      percent = 0;
      display = "";
      timeText = "";
      icon = "";
      return;
    }
    percent = device.percentage || 0;
    const state = stateString(device.state);
    const timeRemaining = state === "Charging" ? device.timeToFull : device.timeToEmpty;
    timeText = formatTime(timeRemaining);
    display = showTime && timeText ? `${timeText}` : `${percent.toFixed(0)}%`;
    icon = batteryIcon(percent, state);
  }

  Component.onCompleted: createUpower()

  Connections {
    target: upower
    function onDisplayDeviceChanged() { updateBattery(); }
    function onOnBatteryChanged() { updateBattery(); }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: updateBattery()
  }

  Label {
    id: label
    text: icon ? `${icon} ${display}` : display
    color: {
      if (!available || !upower || !upower.displayDevice)
        return Theme.colors.text;
      const state = stateString(upower.displayDevice.state);
      if (state === "Charging")
        return Theme.colors.green;
      if (state === "Discharging")
        return Theme.colors.red;
      return Theme.colors.text;
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: {
      showTime = !showTime;
      updateBattery();
    }
  }
}
