import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import ".."
import "../components"

ModuleContainer {
  id: root
  property string iconOff: "󰂲"
  property string iconOn: "󰂰"
  property string iconDisabled: "󰂱"
  property string iconConnected: ""
  property string onClickCommand: "runapp kitty -o tab_bar_style=hidden --class bluetui -e 'bluetui'"

  readonly property var bluetooth: Bluetooth

  property var adapter: bluetooth.defaultAdapter
  property var devices: bluetooth.devices ? bluetooth.devices.values : []
  property var activeDevice: devices.length > 0 ? devices[0] : null
  property var deviceSnapshot: []
  property int pairedCount: 0
  property int connectedCount: 0
  property string connectedNames: ""
  property var connectedDevice: null
  property int connectedBattery: -1
  property string adapterName: ""

  tooltipTitle: root.tooltipTitleText()
  tooltipText: root.tooltipLabel()
  tooltipHoverable: true
  tooltipContent: Component {
    ColumnLayout {
      spacing: Config.space.sm

      TooltipCard {
        content: [
          InfoRow {
            label: "Status"
            value: root.statusLabel()
          },
          InfoRow {
            label: "Adapter"
            value: root.adapterName
            visible: root.adapterName !== ""
          },
          InfoRow {
            label: "Connected"
            value: root.connectedNames !== "" ? root.connectedNames : "None"
          },
          InfoRow {
            label: "Paired"
            value: root.pairedCount.toString()
          }
        ]
      }

      TooltipCard {
        content: [
          RowLayout {
            spacing: 8
            Layout.fillWidth: true

            MetricBlock {
              Layout.fillWidth: true
              label: "Connected"
              value: root.connectedCount.toString()
              icon: root.iconConnected
              accentColor: Config.green
              fillRatio: Math.min(1, root.connectedCount / 4)
              showFill: false
            }

            MetricBlock {
              Layout.fillWidth: true
              label: "Paired"
              value: root.pairedCount.toString()
              icon: root.iconOn
              accentColor: Config.lavender
              fillRatio: Math.min(1, root.pairedCount / 8)
              showFill: false
            }
          }
        ]
      }

      TooltipCard {
        content: [
          RowLayout {
            spacing: 8
            Layout.fillWidth: true

            MetricBlock {
              Layout.fillWidth: true
              label: "Battery"
              value: root.connectedBattery >= 0 ? root.connectedBattery + "%" : "n/a"
              icon: "󰂎"
              accentColor: Config.pink
              fillRatio: root.connectedBattery >= 0 ? Math.min(1, root.connectedBattery / 100) : 0
              showFill: false
            }

            MetricBlock {
              Layout.fillWidth: true
              label: "Devices"
              value: root.devices.length.toString()
              icon: root.iconOn
              accentColor: Config.green
              fillRatio: Math.min(1, root.devices.length / 8)
              showFill: false
            }
          }
        ]
      }

      TooltipActionsRow {
        ActionChip {
          text: "Open"
          onClicked: Quickshell.execDetached(["sh", "-c", root.onClickCommand])
        }

        ActionChip {
          text: "Refresh"
          onClicked: root.refreshBluetooth()
        }
      }
    }
  }

  function stateColor() {
    if (!adapter)
      return Config.textMuted
    if (!adapter.enabled)
      return Config.red
    if (!activeDevice)
      return Config.textMuted
    return Config.textColor
  }

  function tooltipLabel() {
    if (!adapter)
      return "Bluetooth: off"
    if (!adapter.enabled)
      return "Bluetooth: disabled"
    if (activeDevice) {
      const alias = activeDevice.alias || activeDevice.name || ""
      return "Bluetooth: " + (alias ? alias : "connected")
    }
    return "Bluetooth: on"
  }

  function tooltipTitleText() {
    if (!adapter)
      return "Bluetooth"
    if (!adapter.enabled)
      return "Bluetooth"
    if (activeDevice) {
      const alias = activeDevice.alias || activeDevice.name || ""
      return alias !== "" ? alias : "Bluetooth"
    }
    return "Bluetooth"
  }

  function statusLabel() {
    if (!adapter)
      return "Off"
    if (!adapter.enabled)
      return "Disabled"
    return connectedCount > 0 ? "Connected" : "On"
  }

  function deviceLabel(device) {
    if (!device)
      return ""
    return device.alias || device.name || device.address || ""
  }

  function refreshBluetooth() {
    const list = root.devices || []
    root.deviceSnapshot = list.slice(0)
    root.pairedCount = 0
    root.connectedCount = 0
    root.connectedDevice = null
    root.connectedBattery = -1
    root.connectedNames = ""
    const names = []
    for (let i = 0; i < list.length; i++) {
      const device = list[i]
      if (!device)
        continue
      if (device.paired)
        root.pairedCount += 1
      if (device.connected) {
        root.connectedCount += 1
        if (!root.connectedDevice)
          root.connectedDevice = device
        const label = root.deviceLabel(device)
        if (label)
          names.push(label)
        if (root.connectedBattery < 0) {
          const battery = Number.isFinite(device.batteryPercentage)
            ? Math.round(device.batteryPercentage)
            : (Number.isFinite(device.battery) ? Math.round(device.battery) : -1)
          if (battery >= 0)
            root.connectedBattery = battery
        }
      }
    }
    root.connectedNames = names.join(", ")
    root.adapterName = adapter && adapter.name ? adapter.name : ""
  }

  function displayText() {
    if (!adapter)
      return root.iconOff
    if (!adapter.enabled)
      return root.iconDisabled
    if (activeDevice) {
      const alias = activeDevice.alias || activeDevice.name || ""
      return root.iconConnected + (alias ? " " + alias : "")
    }
    return root.iconOn
  }

  content: [
    IconLabel { text: root.displayText(); color: root.stateColor() }
  ]

  MouseArea {
    anchors.fill: parent
    onClicked: Quickshell.execDetached(["sh", "-c", root.onClickCommand])
  }

  onTooltipActiveChanged: {
    if (root.tooltipActive)
      root.refreshBluetooth()
  }

  onDevicesChanged: {
    if (root.tooltipActive)
      root.refreshBluetooth()
  }

  onAdapterChanged: {
    if (root.tooltipActive)
      root.refreshBluetooth()
  }
}
