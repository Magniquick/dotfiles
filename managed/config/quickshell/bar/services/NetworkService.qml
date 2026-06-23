pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Networking
import qsnative
import "../components"
import "../../common/JsonUtils.js" as JsonUtils

Item {
  id: root
  visible: false

  property int tooltipUserCount: 0
  readonly property bool tooltipActive: root.tooltipUserCount > 0

  property string connectionState: ""
  property string connectionType: "disconnected" // disconnected | wifi | ethernet
  property string deviceName: ""
  property int frequencyMhz: 0
  property string ipAddress: ""
  property string gateway: ""
  property int signalPercent: 0
  property string ssid: ""
  property var sourceEntries: []
  readonly property bool sourceSwitching: netStatsProvider.sourceSwitching
  readonly property string sourceSwitchingName: netStatsProvider.sourceSwitchingName
  readonly property string sourceError: netStatsProvider.sourceError
  readonly property bool nativeNetworkBackend: Networking.backend === NetworkBackendType.NetworkManager
  readonly property var connectedDevice: root.findConnectedDevice()
  readonly property var connectedWifiNetwork: root.findConnectedWifiNetwork()
  property var sourceNetworksById: ({})

  // Ethernet/USB NIC details
  property string ethernetSubsystem: ""
  property string ethernetDeviceLabel: ""
  property string lastEthernetDevice: ""

  // Traffic monitoring
  readonly property double rxBytesPerSec: netStatsProvider.rxBytesPerSec
  readonly property double txBytesPerSec: netStatsProvider.txBytesPerSec
  property var rxHistory: []
  property var txHistory: []
  readonly property real trafficScaleMax: netStatsProvider.trafficScaleMax

  function addTooltipUser() {
    root.tooltipUserCount = Math.max(0, root.tooltipUserCount + 1)
  }

  function removeTooltipUser() {
    root.tooltipUserCount = Math.max(0, root.tooltipUserCount - 1)
  }

  function refreshNetwork() {
    root.syncNativeState()
    ipAddressRunner.trigger()
    gatewayRunner.trigger()
    root.refreshSources()
    root.readTrafficSample()
    if (root.connectionType === "ethernet" && root.connectionState === "connected") {
      root.refreshEthernetMetadata()
    }
  }

  function findConnectedDevice() {
    if (!root.nativeNetworkBackend)
      return null

    const devices = Networking.devices
    const deviceCount = JsonUtils.modelCount(devices)
    let fallbackEthernet = null

    for (let i = 0; i < deviceCount; i++) {
      const device = JsonUtils.modelAt(devices, i)
      if (!device || !device.connected)
        continue
      if (device.type === DeviceType.Wifi)
        return device
      if (!fallbackEthernet)
        fallbackEthernet = device
    }

    return fallbackEthernet
  }

  function findConnectedWifiNetwork() {
    const wifiDevice = root.connectedDevice
    if (!wifiDevice || wifiDevice.type !== DeviceType.Wifi)
      return null

    const networks = wifiDevice.networks
    const networkCount = JsonUtils.modelCount(networks)
    for (let i = 0; i < networkCount; i++) {
      const network = JsonUtils.modelAt(networks, i)
      if (network && network.connected)
        return network
    }

    return null
  }

  function setWifiScannerEnabled(enabled) {
    if (!root.nativeNetworkBackend)
      return
    const devices = Networking.devices
    const deviceCount = JsonUtils.modelCount(devices)
    for (let i = 0; i < deviceCount; i++) {
      const device = JsonUtils.modelAt(devices, i)
      if (!device || device.type !== DeviceType.Wifi || device.scannerEnabled === enabled)
        continue
      device.scannerEnabled = enabled
    }
  }

  function syncNativeState() {
    if (!root.nativeNetworkBackend) {
      root.connectionType = "disconnected"
      root.connectionState = ""
      root.deviceName = ""
      root.ssid = ""
      root.signalPercent = 0
      root.frequencyMhz = 0
      root.ethernetSubsystem = ""
      root.ethernetDeviceLabel = ""
      root.lastEthernetDevice = ""
      root.ipAddress = ""
      root.gateway = ""
      root.resetTraffic()
      return
    }

    const device = root.connectedDevice
    const wifiNetwork = root.connectedWifiNetwork
    const nextType = !device ? "disconnected" : (device.type === DeviceType.Wifi ? "wifi" : "ethernet")
    const nextDeviceName = device ? String(device.name || "") : ""
    const nextSsid = wifiNetwork ? String(wifiNetwork.name || "") : ""
    const nextSignalPercent = wifiNetwork && isFinite(wifiNetwork.signalStrength) ? Math.max(0, Math.min(100, Math.round(wifiNetwork.signalStrength * 100))) : 0
    const deviceChanged = root.deviceName !== nextDeviceName
    const typeChanged = root.connectionType !== nextType

    root.connectionType = nextType
    root.connectionState = device ? "connected" : ""
    root.deviceName = nextDeviceName
    root.ssid = nextSsid
    root.signalPercent = nextSignalPercent
    root.frequencyMhz = 0

    if (deviceChanged || typeChanged) {
      root.ipAddress = ""
      root.gateway = ""
      root.resetTraffic()
    }

    if (nextType !== "ethernet") {
      root.ethernetSubsystem = ""
      root.ethernetDeviceLabel = ""
      root.lastEthernetDevice = ""
    } else {
      const ethernetDeviceChanged = root.lastEthernetDevice !== nextDeviceName
      root.lastEthernetDevice = nextDeviceName
      if (ethernetDeviceChanged) {
        root.ethernetSubsystem = ""
        root.ethernetDeviceLabel = ""
      }
    }
  }

  function collectNativeSourceEntries() {
    const entries = []
    const networkObjects = {}
    const devices = Networking.devices
    const deviceCount = JsonUtils.modelCount(devices)

    for (let i = 0; i < deviceCount; i++) {
      const device = JsonUtils.modelAt(devices, i)
      if (!device)
        continue
      const deviceName = String(device.name || "").trim()
      const isWifi = device.type === DeviceType.Wifi
      if (isWifi) {
        const networks = device.networks
        const networkCount = JsonUtils.modelCount(networks)
        for (let j = 0; j < networkCount; j++) {
          const network = JsonUtils.modelAt(networks, j)
          if (!network)
            continue
          const networkName = String(network.name || "").trim()
          if (networkName === "")
            continue
          const known = network.known === undefined ? true : !!network.known
          if (!known && !network.connected)
            continue
          const sourceId = "wifi:" + deviceName + ":" + networkName
          entries.push({
            id: sourceId,
            type: "wifi",
            name: networkName,
            device: deviceName,
            active: !!network.connected,
            connectable: true
          })
          networkObjects[sourceId] = network
        }
        continue
      }

      if (!!device.connected) {
        entries.push({
          id: "ethernet:" + deviceName,
          type: "ethernet",
          name: "Wired",
          device: deviceName,
          active: true,
          connectable: false
        })
      }
    }

    root.sourceNetworksById = networkObjects
    return entries
  }

  function refreshSources() {
    if (!root.nativeNetworkBackend) {
      root.sourceEntries = []
      root.sourceNetworksById = ({})
      netStatsProvider.setSourceEntries("[]")
      return
    }

    const rawEntries = root.collectNativeSourceEntries()
    netStatsProvider.setSourceEntries(JSON.stringify(rawEntries))
    root.sourceEntries = JSON.parse(netStatsProvider.sourceEntriesJson || "[]")
    if (!root.sourceSwitching)
      sourceSwitchTimeoutTimer.stop()
  }

  function switchSource(source) {
    const entry = typeof source === "object" ? source : null
    const name = entry ? String(entry.name || "").trim() : String(source || "").trim()
    if (name === "" || root.sourceSwitching)
      return
    if (entry && !!entry.active)
      return
    if (!netStatsProvider.beginSourceSwitch(name))
      return
    sourceSwitchTimeoutTimer.restart()

    const network = entry ? root.sourceNetworksById[String(entry.id || "")] : null
    if (network && typeof network.connect === "function") {
      try {
        network.connect()
      } catch (err) {
        netStatsProvider.failSourceSwitch("Unable to switch source")
        sourceSwitchTimeoutTimer.stop()
      }
      return
    }

    netStatsProvider.failSourceSwitch("Native networking backend unavailable")
    sourceSwitchTimeoutTimer.stop()
  }

  function refreshNativeStateFromSignal() {
    root.syncNativeState()
    if (root.tooltipActive) {
      root.refreshSources()
      if (root.connectionType === "ethernet" && root.connectionState === "connected")
        root.refreshEthernetMetadata()
    }
  }

  function applyEthernetMetadata(metadata) {
    if (root.connectionType !== "ethernet" || root.connectionState !== "connected")
      return
    root.ethernetSubsystem = String(metadata.subsystem || "")
    root.ethernetDeviceLabel = String(metadata.label || "")
  }

  function refreshEthernetMetadata() {
    if (root.connectionType !== "ethernet" || root.connectionState !== "connected" || root.deviceName === "")
      return

    try {
      root.applyEthernetMetadata(JSON.parse(netStatsProvider.ethernetMetadataJson(root.deviceName) || "{}"))
    } catch (err) {
      root.ethernetSubsystem = ""
      root.ethernetDeviceLabel = ""
    }
  }

  function updateIpAddressDetails(text) {
    root.ipAddress = netStatsProvider.parseIpAddressJson(text || "")
  }

  function updateGatewayDetails(text) {
    root.gateway = netStatsProvider.parseGatewayJson(text || "")
  }

  function readTrafficSample() {
    if (!root.deviceName)
      return
    netStatsProvider.refresh()
  }

  function resetTraffic() {
    netStatsProvider.resetTraffic()
    root.rxHistory = []
    root.txHistory = []
  }

  function updateTrafficRates(rxBytes, txBytes, now) {
    netStatsProvider.updateTrafficRates(rxBytes, txBytes, now)
    root.rxHistory = JSON.parse(netStatsProvider.rxHistoryJson || "[]")
    root.txHistory = JSON.parse(netStatsProvider.txHistoryJson || "[]")
  }

  onTooltipActiveChanged: {
    root.setWifiScannerEnabled(root.tooltipActive)
    if (root.tooltipActive) {
      root.refreshNetwork()
    } else {
      root.resetTraffic()
      netStatsProvider.clearSourceSwitch()
      sourceSwitchTimeoutTimer.stop()
    }
  }

  Component.onCompleted: {
    root.syncNativeState()
    root.refreshSources()
  }

  CommandRunner {
    id: ipAddressRunner

    // Quickshell.Networking gives us device/network state, but not the
    // active IPv4 address on the current backend.
    command: root.deviceName ? ["ip", "-j", "-4", "addr", "show", "dev", root.deviceName, "scope", "global"] : []
    enabled: root.tooltipActive && root.connectionState === "connected" && root.deviceName !== ""
    intervalMs: 30000

    onRan: function (commandOutput) {
      root.updateIpAddressDetails(commandOutput)
    }
  }

  CommandRunner {
    id: gatewayRunner

    // Quickshell.Networking gives us device/network state, but not the
    // default gateway on the current backend.
    command: root.deviceName ? ["ip", "-j", "route", "show", "default", "dev", root.deviceName] : []
    enabled: root.tooltipActive && root.connectionState === "connected" && root.deviceName !== ""
    intervalMs: 30000

    onRan: function (commandOutput) {
      root.updateGatewayDetails(commandOutput)
    }
  }

  Connections {
    target: Networking

    function onWifiEnabledChanged() {
      root.refreshNativeStateFromSignal()
    }

    function onWifiHardwareEnabledChanged() {
      root.refreshNativeStateFromSignal()
    }
  }

  Connections {
    target: Networking.devices

    function onObjectInsertedPost(object, index) {
      root.refreshNativeStateFromSignal()
    }

    function onObjectRemovedPost(object, index) {
      root.refreshNativeStateFromSignal()
    }
  }

  Repeater {
    model: root.nativeNetworkBackend ? Networking.devices : null

    delegate: Item {
      id: deviceWatcher

      required property var modelData

      Connections {
        target: deviceWatcher.modelData

        function onConnectedChanged() {
          root.refreshNativeStateFromSignal()
        }

        function onNameChanged() {
          root.refreshNativeStateFromSignal()
        }

        function onStateChanged() {
          root.refreshNativeStateFromSignal()
        }
      }

      Connections {
        target: deviceWatcher.modelData && deviceWatcher.modelData.networks ? deviceWatcher.modelData.networks : null

        function onObjectInsertedPost(object, index) {
          root.refreshNativeStateFromSignal()
        }

        function onObjectRemovedPost(object, index) {
          root.refreshNativeStateFromSignal()
        }
      }

      Repeater {
        model: deviceWatcher.modelData && deviceWatcher.modelData.networks ? deviceWatcher.modelData.networks : null

        delegate: Item {
          id: networkWatcher

          required property var modelData

          Connections {
            target: networkWatcher.modelData

            function onConnectedChanged() {
              root.refreshNativeStateFromSignal()
            }

            function onKnownChanged() {
              if (root.tooltipActive)
                root.refreshSources()
            }

            function onStateChanged() {
              root.refreshNativeStateFromSignal()
            }

            function onStateChangingChanged() {
              root.refreshNativeStateFromSignal()
            }

            function onSignalStrengthChanged() {
              root.refreshNativeStateFromSignal()
            }
          }
        }
      }
    }
  }

  NetStatsProvider {
    id: netStatsProvider
    device: root.deviceName

    onSampleReady: function (rxBytes, txBytes) {
      root.updateTrafficRates(rxBytes, txBytes, Date.now())
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.tooltipActive && root.deviceName !== "" && root.connectionState === "connected"
    onTriggered: root.readTrafficSample()
  }

  Timer {
    id: sourceSwitchTimeoutTimer

    interval: 12000
    running: false
    repeat: false

    onTriggered: {
      if (!root.sourceSwitching)
        return
      netStatsProvider.failSourceSwitch("Switch request timed out")
    }
  }
}
