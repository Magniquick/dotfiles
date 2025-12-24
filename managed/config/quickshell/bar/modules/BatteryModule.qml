import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import ".."
import "../components"

ModuleContainer {
  id: root
  property bool showTime: false
  property int healthPercent: -1
  property real healthEnergyFull: NaN
  property real healthEnergyDesign: NaN
  tooltipTitle: "Battery"
  tooltipText: root.tooltipLabel()
  tooltipHoverable: true
  tooltipContent: Component {
    ColumnLayout {
      spacing: Config.space.sm

      TooltipCard {
        content: [
          InfoRow {
            label: "Status"
            value: root.stateLabel(UPower.displayDevice)
          },
          InfoRow {
            label: "Charge"
            value: root.percentLabel(UPower.displayDevice)
          },
          InfoRow {
            label: "Health"
            value: root.healthLabel()
          },
          InfoRow {
            label: "Time"
            value: root.timeLabel(UPower.displayDevice)
            visible: root.timeLabel(UPower.displayDevice) !== ""
          }
        ]
      }

      ProgressBar {
        value: root.batteryPercentValue(UPower.displayDevice) / 100
        fillColor: root.batteryColor(UPower.displayDevice)
        trackColor: Config.moduleBackgroundMuted
      }

      TooltipActionsRow {
        ActionChip {
          text: root.showTime ? "Show percent" : "Show time"
          onClicked: root.showTime = !root.showTime
        }
      }
    }
  }

  function formatSeconds(seconds) {
    if (!seconds || seconds <= 0)
      return ""
    const totalMinutes = Math.floor(seconds / 60)
    const hours = Math.floor(totalMinutes / 60)
    const minutes = totalMinutes % 60
    if (hours <= 0)
      return minutes + "m"
    if (minutes <= 0)
      return hours + "h"
    return hours + "h " + minutes + "m"
  }

  function timeLabel(device) {
    if (!device || !device.ready)
      return ""
    const time = device.timeToEmpty > 0 ? device.timeToEmpty : device.timeToFull
    const formatted = formatSeconds(time)
    return formatted ? formatted : ""
  }

  function percentLabel(device) {
    if (!device || !device.ready)
      return ""
    const rawPercent = device.percentage
    const percent = rawPercent <= 1 ? rawPercent * 100 : rawPercent
    return Math.round(percent) + "%"
  }

  function batteryPercentValue(device) {
    if (!device || !device.ready)
      return 0
    const rawPercent = device.percentage
    const percent = rawPercent <= 1 ? rawPercent * 100 : rawPercent
    return Math.max(0, Math.min(100, percent))
  }

  function healthLabel() {
    return root.healthPercent >= 0 ? root.healthPercent + "%" : "—"
  }

  function batteryColor(device) {
    if (!device || !device.ready)
      return Config.textColor
    if (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge)
      return Config.green
    if (device.state === UPowerDeviceState.Discharging || device.state === UPowerDeviceState.PendingDischarge)
      return Config.red
    return Config.textColor
  }

  function batteryIcon(device) {
    if (!device || !device.ready)
      return ""
    if (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge)
      return "󰂄"
    const rawPercent = device.percentage
    const percent = rawPercent <= 1 ? rawPercent * 100 : rawPercent
    if (percent <= 10)
      return ""
    if (percent <= 35)
      return ""
    if (percent <= 65)
      return ""
    if (percent <= 85)
      return ""
    return ""
  }

  function parseHealthMetrics(lines) {
    let capacityValue = NaN
    let energyFull = NaN
    let energyDesign = NaN
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim()
      if (line.indexOf("capacity:") === 0) {
        const match = line.match(/capacity:\s*([0-9.]+)%/i)
        if (match)
          capacityValue = parseFloat(match[1])
      } else if (line.indexOf("energy-full-design:") === 0) {
        const match = line.match(/energy-full-design:\s*([0-9.]+)/i)
        if (match)
          energyDesign = parseFloat(match[1])
      } else if (line.indexOf("energy-full:") === 0) {
        const match = line.match(/energy-full:\s*([0-9.]+)/i)
        if (match)
          energyFull = parseFloat(match[1])
      }
    }
    return { capacityValue: capacityValue, energyFull: energyFull, energyDesign: energyDesign }
  }

  function updateHealth(output) {
    if (!output || output.trim() === "") {
      root.updateHealthFallback()
      return
    }
    const metrics = root.parseHealthMetrics(output.split("\n"))
    if (isFinite(metrics.energyFull))
      root.healthEnergyFull = metrics.energyFull
    if (isFinite(metrics.energyDesign))
      root.healthEnergyDesign = metrics.energyDesign
    if (isFinite(metrics.capacityValue)) {
      root.healthPercent = Math.round(metrics.capacityValue)
      return
    }
    if (isFinite(root.healthEnergyFull) && isFinite(root.healthEnergyDesign) && root.healthEnergyDesign > 0) {
      root.healthPercent = Math.round((root.healthEnergyFull / root.healthEnergyDesign) * 100)
      return
    }
    if (root.healthPercent < 0)
      root.updateHealthFallback()
  }

  function updateHealthFallback() {
    const device = UPower.displayDevice
    if (!device || !device.ready || !device.healthSupported)
      return
    const percent = device.healthPercentage
    if (isFinite(percent))
      root.healthPercent = Math.round(percent)
  }

  function stateLabel(device) {
    if (!device || !device.ready)
      return "Unknown"
    switch (device.state) {
      case UPowerDeviceState.Charging:
      case UPowerDeviceState.PendingCharge:
        return "Charging"
      case UPowerDeviceState.Discharging:
      case UPowerDeviceState.PendingDischarge:
        return "Discharging"
      case UPowerDeviceState.FullyCharged:
        return "Full"
      default:
        return "Idle"
    }
  }

  function tooltipLabel() {
    const device = UPower.displayDevice
    if (!device || !device.ready)
      return "Battery: unknown"
    const percentText = root.percentLabel(device)
    const timeText = root.timeLabel(device)
    const timeSuffix = timeText ? " (" + timeText + ")" : ""
    return "Battery: " + percentText + timeSuffix
  }

  CommandRunner {
    id: healthRunner
    intervalMs: 0
    enabled: root.tooltipActive
    command: "upower --battery"
    onRan: function(output) {
      root.updateHealth(output)
    }
    onOutputChanged: root.updateHealth(output)
    onEnabledChanged: {
      if (enabled)
        trigger()
    }
  }

  onTooltipActiveChanged: {
    if (root.tooltipActive)
      healthRunner.trigger()
  }

  content: [
    IconTextRow {
      spacing: root.contentSpacing
      iconText: root.batteryIcon(UPower.displayDevice)
      iconColor: root.batteryColor(UPower.displayDevice)
      text: root.showTime
        ? root.timeLabel(UPower.displayDevice)
        : root.percentLabel(UPower.displayDevice)
      textColor: root.batteryColor(UPower.displayDevice)
    }
  ]

  MouseArea {
    anchors.fill: parent
    onClicked: root.showTime = !root.showTime
  }
}
