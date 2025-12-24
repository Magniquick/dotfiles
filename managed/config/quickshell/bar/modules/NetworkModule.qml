import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"

ModuleContainer {
  id: root
  property string iconText: "󰖪"
  property string ssid: ""
  property int signalPercent: 0
  property int frequencyMhz: 0
  property string deviceName: ""
  property string ipAddress: ""
  property string gateway: ""
  property double rxBytesPerSec: 0
  property double txBytesPerSec: 0
  property double lastRxBytes: 0
  property double lastTxBytes: 0
  property double lastTrafficSampleMs: 0
  readonly property double trafficPeak: Math.max(1, Math.max(root.rxBytesPerSec, root.txBytesPerSec))
  property string connectionType: "disconnected"
  property string connectionState: ""
  property string onClickCommand: "runapp kitty -o tab_bar_style=hidden --class impala -e 'impala'"
  tooltipTitle: root.connectionType === "wifi"
    ? (root.ssid !== "" ? root.ssid : "Wi-Fi")
    : (root.connectionType === "ethernet" ? "Ethernet" : "Network")
  tooltipText: root.tooltipLabel()
  tooltipHoverable: true
  tooltipContent: Component {
    ColumnLayout {
      spacing: Config.space.sm

      TooltipCard {
        content: [
          InfoRow {
            label: "Status"
            value: root.connectionLabel()
          },
          InfoRow {
            label: "Device"
            value: root.deviceName
            visible: root.deviceName !== ""
          },
          InfoRow {
            label: "IP"
            value: root.ipAddress
            visible: root.ipAddress !== ""
          },
          InfoRow {
            label: "Gateway"
            value: root.gateway
            visible: root.gateway !== ""
          }
        ]
      }

      TooltipCard {
        visible: root.connectionType === "wifi" && root.connectionState === "connected"
        content: [
          RowLayout {
            spacing: 8
            Layout.fillWidth: true

            MetricBlock {
              Layout.fillWidth: true
              label: "Signal"
              value: root.signalPercent > 0 ? root.signalPercent + "%" : "n/a"
              icon: root.iconForSignal()
              accentColor: Config.green
              fillRatio: Math.max(0, Math.min(1, root.signalPercent / 100))
              showFill: false
            }

            MetricBlock {
              Layout.fillWidth: true
              label: "Frequency"
              value: root.formatFrequency(root.frequencyMhz) || "n/a"
              icon: "󰖩"
              accentColor: Config.lavender
              fillRatio: root.frequencyMhz > 0 ? Math.min(1, root.frequencyMhz / 6000) : 0
              showFill: false
            }
          }
        ]
      }

      TooltipCard {
        visible: root.connectionType === "wifi" && root.connectionState === "connected"
        content: [
          RowLayout {
            spacing: 8
            Layout.fillWidth: true

            MetricBlock {
              id: upMetric
              Layout.fillWidth: true
              Layout.preferredWidth: Math.max(upMetric.implicitWidth, downMetric.implicitWidth)
              label: "Up"
              value: root.formatRate(root.txBytesPerSec)
              icon: "↑"
              accentColor: Config.pink
              fillRatio: root.txBytesPerSec / root.trafficPeak
              showFill: false
            }

            MetricBlock {
              id: downMetric
              Layout.fillWidth: true
              Layout.preferredWidth: Math.max(upMetric.implicitWidth, downMetric.implicitWidth)
              label: "Down"
              value: root.formatRate(root.rxBytesPerSec)
              icon: "↓"
              accentColor: Config.green
              fillRatio: root.rxBytesPerSec / root.trafficPeak
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
          onClicked: root.refreshNetwork()
        }
      }
    }
  }

  property var wifiIcons: ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
  property string ethernetIcon: "󰈀"
  property string linkedIcon: "󰤣"
  property string disconnectedIcon: "󰖪"

  function tooltipLabel() {
    if (root.connectionType === "wifi") {
      if (!root.ssid || root.connectionState !== "connected")
        return "Wi-Fi: disconnected"
      const gatewayText = root.gateway ? " (" + root.gateway + ")" : ""
      const lines = [root.ssid + gatewayText]
      if (root.ipAddress)
        lines.push("IP: " + root.ipAddress)
      if (root.signalPercent > 0)
        lines.push("Signal strength: " + root.signalPercent + "%")
      const frequencyText = root.formatFrequency(root.frequencyMhz)
      if (frequencyText)
        lines.push("Frequency: " + frequencyText)
      const speedText = root.speedText()
      if (speedText)
        lines.push("Speed: " + speedText)
      return lines.join("\n")
    }
    if (root.connectionType === "ethernet") {
      if (root.connectionState === "connected (externally)")
        return "Network: linked"
      return root.connectionState === "connected"
        ? "Wired: connected"
        : "Wired: disconnected"
    }
    return "Network: disconnected"
  }

  function connectionLabel() {
    if (root.connectionType === "wifi")
      return root.connectionState === "connected" ? "Wi-Fi connected" : "Wi-Fi disconnected"
    if (root.connectionType === "ethernet") {
      if (root.connectionState === "connected (externally)")
        return "Ethernet linked"
      return root.connectionState === "connected"
        ? "Ethernet connected"
        : "Ethernet disconnected"
    }
    return "Offline"
  }

  function refreshNetwork() {
    statusRunner.trigger()
    wifiRunner.trigger()
    ipRunner.trigger()
    trafficRunner.trigger()
  }

  function formatFrequency(mhz) {
    if (!mhz || mhz <= 0)
      return ""
    const ghz = mhz / 1000
    return ghz.toFixed(1) + " GHz"
  }

  function formatRate(bytesPerSecond) {
    if (!bytesPerSecond || bytesPerSecond <= 0)
      return "0B/s"
    const units = ["B/s", "KB/s", "MB/s", "GB/s"]
    let value = bytesPerSecond
    let unitIndex = 0
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024
      unitIndex += 1
    }
    const decimals = value >= 100 ? 0 : 1
    return value.toFixed(decimals) + units[unitIndex]
  }

  function speedText() {
    if (root.rxBytesPerSec <= 0 && root.txBytesPerSec <= 0)
      return ""
    return "↑ " + root.formatRate(root.txBytesPerSec) +
      " ↓ " + root.formatRate(root.rxBytesPerSec)
  }

  function resetTraffic() {
    root.rxBytesPerSec = 0
    root.txBytesPerSec = 0
    root.lastRxBytes = 0
    root.lastTxBytes = 0
    root.lastTrafficSampleMs = 0
  }

  function clearWifiDetails() {
    root.ssid = ""
    root.signalPercent = 0
    root.frequencyMhz = 0
    root.ipAddress = ""
    root.gateway = ""
    root.resetTraffic()
  }

  function iconForSignal() {
    const percent = root.signalPercent
    if (percent <= 0)
      return root.wifiIcons[0]
    if (percent < 25)
      return root.wifiIcons[1]
    if (percent < 50)
      return root.wifiIcons[2]
    if (percent < 75)
      return root.wifiIcons[3]
    return root.wifiIcons[4]
  }

  function findStatusLines(lines) {
    let wifiLine = ""
    let ethernetLine = ""
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].indexOf(":wifi:") > 0)
        wifiLine = lines[i]
      else if (lines[i].indexOf(":ethernet:") > 0)
        ethernetLine = lines[i]
    }
    return { wifiLine: wifiLine, ethernetLine: ethernetLine }
  }

  function applyWifiStatus(wifiLine, wasWifiConnected) {
    if (!wifiLine)
      return false
    const parts = wifiLine.split(":")
    root.deviceName = parts[0] || ""
    root.connectionType = "wifi"
    root.connectionState = parts[2] || ""
    const connection = parts.slice(3).join(":")
    root.ssid = connection && connection !== "--" ? connection : ""
    if (root.connectionState === "connected") {
      if (!wasWifiConnected)
        root.resetTraffic()
      ipRunner.trigger()
      trafficRunner.trigger()
      root.iconText = root.iconForSignal()
      return true
    }
    return false
  }

  function applyEthernetStatus(ethernetLine) {
    if (!ethernetLine)
      return false
    const parts = ethernetLine.split(":")
    root.connectionType = "ethernet"
    root.connectionState = parts[2] || ""
    if (root.connectionState === "connected") {
      root.iconText = root.ethernetIcon
      root.clearWifiDetails()
      return true
    }
    if (root.connectionState === "connected (externally)")
      root.iconText = root.linkedIcon
    return false
  }

  function updateStatus(text) {
    if (!text)
      return
    const wasWifiConnected = root.connectionType === "wifi" && root.connectionState === "connected"
    const lines = text.trim().split("\n")
    const statusLines = root.findStatusLines(lines)
    if (root.applyWifiStatus(statusLines.wifiLine, wasWifiConnected))
      return
    if (root.applyEthernetStatus(statusLines.ethernetLine))
      return
    root.connectionType = "disconnected"
    root.connectionState = ""
    root.iconText = root.disconnectedIcon
    root.clearWifiDetails()
  }

  function parseWifiSignal(lines) {
    let signalValue = 0
    let ssidValue = ""
    let frequencyValue = 0
    for (let i = 0; i < lines.length; i++) {
      const parts = lines[i].split(":")
      if (parts[0] === "yes") {
        signalValue = parseInt(parts[1] || "0", 10)
        ssidValue = parts[2] || ""
        frequencyValue = parseInt(parts[3] || "0", 10)
        break
      }
    }
    return {
      signalPercent: isNaN(signalValue) ? 0 : signalValue,
      ssid: ssidValue,
      frequencyMhz: isNaN(frequencyValue) ? 0 : frequencyValue
    }
  }

  function updateSignal(text) {
    if (!text)
      return
    const details = root.parseWifiSignal(text.trim().split("\n"))
    root.signalPercent = details.signalPercent
    if (details.ssid)
      root.ssid = details.ssid
    root.frequencyMhz = details.frequencyMhz
    if (root.connectionType === "wifi" && root.connectionState === "connected")
      root.iconText = root.iconForSignal()
  }

  function parseIpDetails(lines) {
    let ipValue = ""
    let gatewayValue = ""
    for (let i = 0; i < lines.length; i++) {
      const parts = lines[i].split(":")
      const key = parts[0]
      const value = parts.slice(1).join(":")
      if (key.indexOf("IP4.ADDRESS") === 0 && !ipValue)
        ipValue = value
      else if (key === "IP4.GATEWAY")
        gatewayValue = value
    }
    return { ipAddress: ipValue, gateway: gatewayValue }
  }

  function updateIpDetails(text) {
    if (!text || text.trim() === "") {
      root.ipAddress = ""
      root.gateway = ""
      return
    }
    const details = root.parseIpDetails(text.trim().split("\n"))
    root.ipAddress = details.ipAddress
    root.gateway = details.gateway
  }

  function parseTrafficBytes(lines) {
    if (lines.length < 2)
      return { valid: false, rxBytes: NaN, txBytes: NaN }
    const rxBytes = parseFloat(lines[0])
    const txBytes = parseFloat(lines[1])
    if (!isFinite(rxBytes) || !isFinite(txBytes))
      return { valid: false, rxBytes: NaN, txBytes: NaN }
    return { valid: true, rxBytes: rxBytes, txBytes: txBytes }
  }

  function updateTrafficRates(rxBytes, txBytes, now) {
    if (root.lastTrafficSampleMs > 0 && now > root.lastTrafficSampleMs) {
      const deltaSeconds = (now - root.lastTrafficSampleMs) / 1000
      const rxDelta = rxBytes - root.lastRxBytes
      const txDelta = txBytes - root.lastTxBytes
      if (rxDelta >= 0 && txDelta >= 0 && deltaSeconds > 0) {
        root.rxBytesPerSec = rxDelta / deltaSeconds
        root.txBytesPerSec = txDelta / deltaSeconds
      } else {
        root.rxBytesPerSec = 0
        root.txBytesPerSec = 0
      }
    }
    root.lastRxBytes = rxBytes
    root.lastTxBytes = txBytes
    root.lastTrafficSampleMs = now
  }

  function updateTraffic(text) {
    if (!text || text.trim() === "")
      return
    const parsed = root.parseTrafficBytes(text.trim().split("\n"))
    if (!parsed.valid)
      return
    root.updateTrafficRates(parsed.rxBytes, parsed.txBytes, Date.now())
  }

  CommandRunner {
    id: statusRunner
    intervalMs: 5000
    command: "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev status"
    onOutputChanged: root.updateStatus(output)
  }

  CommandRunner {
    id: wifiRunner
    intervalMs: 7000
    command: "nmcli -t -f ACTIVE,SIGNAL,SSID,FREQ dev wifi"
    onOutputChanged: root.updateSignal(output)
  }

  CommandRunner {
    id: ipRunner
    intervalMs: 12000
    enabled: root.tooltipActive &&
      root.connectionType === "wifi" &&
      root.connectionState === "connected" &&
      root.deviceName !== ""
    command: root.deviceName
      ? "nmcli -t -f IP4.ADDRESS,IP4.GATEWAY dev show " + root.deviceName
      : ""
    onOutputChanged: root.updateIpDetails(output)
  }

  CommandRunner {
    id: trafficRunner
    intervalMs: 1000
    enabled: root.tooltipActive &&
      root.connectionType === "wifi" &&
      root.connectionState === "connected" &&
      root.deviceName !== ""
    command: root.deviceName
      ? "cat /sys/class/net/" + root.deviceName + "/statistics/rx_bytes /sys/class/net/" + root.deviceName + "/statistics/tx_bytes"
      : ""
    onOutputChanged: root.updateTraffic(output)
  }

  onTooltipActiveChanged: {
    if (root.tooltipActive) {
      ipRunner.trigger()
      trafficRunner.trigger()
    } else {
      root.resetTraffic()
    }
  }

  content: [
    IconLabel { text: root.iconText; color: Config.flamingo }
  ]

  MouseArea {
    anchors.fill: parent
    onClicked: Quickshell.execDetached(["sh", "-c", root.onClickCommand])
  }
}
