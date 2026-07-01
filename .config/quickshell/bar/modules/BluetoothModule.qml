/**
 * @module BluetoothModule
 * @description Bluetooth status and device management module
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Quickshell.Io
import qsnative
import ".."
import "../components"
import "../../common" as Common

ModuleContainer {
  id: root

  readonly property var bluetooth: Bluetooth
  property var adapter: bluetooth.defaultAdapter
  property var devices: adapter && adapter.devices ? adapter.devices.values : []
  property var deviceSnapshot: []
  property var deviceInfoByKey: ({})

  property string iconConnected: ""
  property string iconDisabled: "󰂲"
  property string iconOn: "󰂯"
  property string iconOff: "󰂲"
  property string iconScanning: "󰂰"
  property string onClickCommand: "runapp kitty -o tab_bar_style=hidden --class bluetui -e 'bluetui'"

  property int connectedCount: 0
  property int connectedBattery: -1
  property int librepodsBattery: -1
  property int librepodsBatteryLeft: -1
  property int librepodsBatteryRight: -1
  property int librepodsBatteryCase: -1
  property string connectedNames: ""
  property bool detailsExpanded: false
  property string pendingDeviceKey: ""
  property bool pendingConnect: false
  property var pendingDeviceActions: ({})
  property int deviceActionTimeoutMs: 12000
  property bool scanActive: false
  property bool moduleScanSession: false
  property bool desiredScanState: false
  property int scanEnsureAttempts: 0
  property string lastScanSource: ""
  property string lastScanAction: "none"
  property string lastStartDiscoverySender: ""
  property int lastStartDiscoveryPid: -1
  property string lastStartDiscoveryProcess: ""
  property string lastScanHolders: ""
  property int lastScanStopNotifyMs: 0
  property bool showUnpairedDevices: false
  property bool debugBluetooth: false
  property bool debugLogging: true

  readonly property bool adapterEnabled: !!(root.adapter && root.adapter.enabled)
  readonly property bool adapterDiscovering: !!(root.adapter && root.adapter.discovering)
  readonly property string adapterName: root.adapter && root.adapter.name ? String(root.adapter.name) : "Bluetooth"

  BarModuleLogic {
    id: uiLogic
  }

  BluetoothDiagnosticsProvider {
    id: bluetoothDiagnostics
  }

  Connections {
    target: bluetoothDiagnostics

    function onLast_start_discovery_senderChanged() {
      root.lastStartDiscoverySender = bluetoothDiagnostics.last_start_discovery_sender
      root.lastStartDiscoveryPid = bluetoothDiagnostics.last_start_discovery_pid
      root.lastStartDiscoveryProcess = bluetoothDiagnostics.last_start_discovery_process
      root.logDebug("resolved StartDiscovery caller sender=" + root.lastStartDiscoverySender + " pid=" + root.lastStartDiscoveryPid + " process=" + root.lastStartDiscoveryProcess)
    }

    function onLast_scan_holdersChanged() {
      root.lastScanHolders = bluetoothDiagnostics.last_scan_holders
      if (root.lastScanHolders.length > 0)
        root.logDebug("possible scan holders:\n" + root.lastScanHolders)
      else
        root.logDebug("possible scan holders: none matched")
    }

    function onLibrepods_tooltipChanged() {
      root.applyLibrepodsTooltip(bluetoothDiagnostics.librepods_tooltip)
    }

    function onErrorChanged() {
      if (bluetoothDiagnostics.error.length > 0)
        root.logDebug("bluetooth diagnostics: " + bluetoothDiagnostics.error)
    }
  }

  function logDebug(message) {
    if (!root.debugLogging)
      return
    console.log("[BluetoothModule]", new Date().toISOString(), message)
  }

  function deviceLabel(device) {
    const info = root.deviceInfo(device)
    return info && info.label ? String(info.label) : ""
  }

  function deviceTypeIcon(device) {
    const info = root.deviceInfo(device)
    return info && info.icon ? String(info.icon) : "󰂯"
  }

  function deviceKey(device) {
    const info = root.deviceInfo(device)
    if (info && info.key)
      return String(info.key)
    if (!device)
      return ""
    return device.dbusPath || device.address || ""
  }

  function deviceBatteryValue(device) {
    const info = root.deviceInfo(device)
    return info && Number.isFinite(info.battery) ? info.battery : -1
  }

  function parseLibrepodsTooltip(text) {
    const parsed = root.parseLibrepodsTooltipParts(text)
    return parsed.average
  }

  function parseLibrepodsTooltipParts(text) {
    return uiLogic.parseLibrepodsTooltip(String(text || ""))
  }

  function applyLibrepodsTooltip(text) {
    const parsed = root.parseLibrepodsTooltipParts(text)
    if (parsed.average > 0) {
      const changed = parsed.average !== root.librepodsBattery || parsed.left !== root.librepodsBatteryLeft || parsed.right !== root.librepodsBatteryRight || parsed.caseBattery !== root.librepodsBatteryCase

      root.librepodsBattery = parsed.average
      root.librepodsBatteryLeft = parsed.left
      root.librepodsBatteryRight = parsed.right
      root.librepodsBatteryCase = parsed.caseBattery

      root.logDebug("librepods tooltip battery parsed avg=" + parsed.average + " L=" + parsed.left + " R=" + parsed.right + " C=" + parsed.caseBattery)
      if (changed && root.connectedBattery <= 0 && root.connectedCount > 0)
        root.refreshBluetooth()
    } else {
      root.librepodsBattery = -1
      root.librepodsBatteryLeft = -1
      root.librepodsBatteryRight = -1
      root.librepodsBatteryCase = -1
    }
  }

  function isAirpodsDevice(device) {
    const info = root.deviceInfo(device)
    return !!(info && info.airpods)
  }

  function displayBatteryValue(device, directBattery) {
    if (Number.isFinite(directBattery) && directBattery > 0)
      return directBattery
    if (!!(device && device.connected) && root.isAirpodsDevice(device) && root.librepodsBattery > 0)
      return root.librepodsBattery
    return -1
  }

  function librepodsBatterySummary() {
    if (root.librepodsBatteryLeft <= 0 && root.librepodsBatteryRight <= 0 && root.librepodsBatteryCase <= 0)
      return ""

    const parts = []
    if (root.librepodsBatteryLeft > 0)
      parts.push("L " + root.librepodsBatteryLeft.toString() + "%")
    if (root.librepodsBatteryRight > 0)
      parts.push("R " + root.librepodsBatteryRight.toString() + "%")
    if (root.librepodsBatteryCase > 0)
      parts.push("C " + root.librepodsBatteryCase.toString() + "%")
    return parts.join(" ")
  }

  function deviceBatterySuffix(device, directBattery) {
    if (Number.isFinite(directBattery) && directBattery > 0)
      return directBattery.toString() + "%"
    if (!!(device && device.connected) && root.isAirpodsDevice(device)) {
      const summary = root.librepodsBatterySummary()
      if (summary.length > 0)
        return summary
    }
    return ""
  }

  function pendingDeviceAction(device) {
    const key = root.deviceKey(device)
    if (key.length === 0)
      return null
    return root.pendingDeviceActions[key] || null
  }

  function deviceInteractive(device) {
    if (!device || !root.adapterEnabled)
      return false
    if (root.pendingDeviceAction(device) !== null)
      return false
    const state = device.state
    if (state === BluetoothDeviceState.Connecting || state === BluetoothDeviceState.Disconnecting)
      return false
    return true
  }

  function deviceStatusBadge(device) {
    if (!device || !root.adapterEnabled)
      return ""
    const pending = root.pendingDeviceAction(device)
    if (pending)
      return pending.targetConnected ? "CONNECTING" : "DISCONNECTING"
    const state = device.state
    if (state === BluetoothDeviceState.Connecting)
      return "CONNECTING"
    if (state === BluetoothDeviceState.Disconnecting)
      return "DISCONNECTING"
    if (device.connected)
      return "CONNECTED"
    if (device.paired)
      return "PAIRED"
    return root.adapterDiscovering ? "NEW" : ""
  }

  function deviceStatusColor(device) {
    const pending = root.pendingDeviceAction(device)
    if (pending)
      return Qt.alpha(Config.color.secondary, 0.95)
    const state = device ? device.state : undefined
    if (!root.adapterEnabled || state === BluetoothDeviceState.Disconnected)
      return Qt.alpha(Config.color.surface_variant, 0.95)
    if (state === BluetoothDeviceState.Connecting || state === BluetoothDeviceState.Disconnecting)
      return Qt.alpha(Config.color.secondary, 0.95)
    if (device && device.connected)
      return Qt.alpha(Config.color.tertiary, 0.9)
    return Qt.alpha(Config.color.surface_variant, 0.95)
  }

  function deviceStatusTextColor(device) {
    if (root.pendingDeviceAction(device))
      return Config.color.on_secondary
    const state = device ? device.state : undefined
    if (state === BluetoothDeviceState.Connecting || state === BluetoothDeviceState.Disconnecting)
      return Config.color.on_secondary
    if (device && device.connected)
      return Config.color.on_tertiary
    return Config.color.on_surface_variant
  }

  function deviceTrailingIcon(device) {
    if (!root.adapterEnabled)
      return ""
    const pending = root.pendingDeviceAction(device)
    if (pending)
      return pending.targetConnected ? "󱍸" : "󱍹"
    const state = device ? device.state : undefined
    if (state === BluetoothDeviceState.Connecting)
      return "󱍸"
    if (state === BluetoothDeviceState.Disconnecting)
      return "󱍹"
    return device && device.connected ? "󰅖" : "󰐕"
  }

  function deviceSubtitle(device) {
    if (!device)
      return ""

    const parts = []
    const state = device.state
    if (!root.adapterEnabled) {
      parts.push("Adapter disabled")
    } else if (state === BluetoothDeviceState.Connecting || state === BluetoothDeviceState.Disconnecting) {
      // The badge already carries the primary transition state.
    } else if (device.paired) {
      parts.push("Paired")
    } else if (root.adapterDiscovering) {
      parts.push("Available now")
    }

    const battery = root.deviceBatterySuffix(device, root.deviceBatteryValue(device))
    if (battery.length > 0)
      parts.push(battery)

    return parts.join(" • ")
  }

  function statusLabel() {
    if (!root.adapter)
      return "Unavailable"
    if (!root.adapterEnabled)
      return "Disabled"
    if (root.moduleScanSession || root.desiredScanState)
      return "Scanning"
    if (root.connectedCount > 0)
      return "Connected"
    return "Ready"
  }

  function stateColor() {
    if (!root.adapter || !root.adapterEnabled)
      return Config.color.on_surface_variant
    if (root.connectedCount > 0)
      return Config.color.tertiary
    if (root.adapterDiscovering)
      return Config.color.primary
    return Config.color.on_surface
  }

  function displayIcon() {
    if (!root.adapter)
      return root.iconDisabled
    if (!root.adapterEnabled)
      return root.iconOff
    if (root.connectedCount > 0)
      return root.iconConnected
    if (root.moduleScanSession || root.desiredScanState)
      return root.iconScanning
    return root.iconOn
  }

  function sortedDevices(list) {
    const source = list || []
    const infos = uiLogic.bluetoothDevices(source.map((device, index) => root.bluetoothDeviceSummary(device, index)))
    const infoMap = {}
    const sorted = []
    for (let i = 0; i < infos.length; ++i) {
      const info = infos[i]
      const device = source[Number(info.index)]
      if (!device)
        continue
      infoMap[String(info.key)] = info
      sorted.push(device)
    }
    root.deviceInfoByKey = infoMap
    return sorted
  }

  function bluetoothDeviceSummary(device, index) {
    return {
      index: index,
      alias: String(device && device.alias ? device.alias : ""),
      name: String(device && device.name ? device.name : ""),
      address: String(device && device.address ? device.address : ""),
      dbusPath: String(device && device.dbusPath ? device.dbusPath : ""),
      icon: String(device && device.icon ? device.icon : ""),
      connected: !!(device && device.connected),
      paired: !!(device && device.paired),
      batteryPercentage: device && Number.isFinite(device.batteryPercentage) ? Number(device.batteryPercentage) : null,
      battery: device && Number.isFinite(device.battery) ? Number(device.battery) : null
    }
  }

  function deviceInfo(device) {
    if (!device)
      return null
    const dbusPath = String(device.dbusPath || "")
    if (dbusPath.length > 0 && root.deviceInfoByKey[dbusPath])
      return root.deviceInfoByKey[dbusPath]
    const address = String(device.address || "")
    if (address.length > 0 && root.deviceInfoByKey[address])
      return root.deviceInfoByKey[address]
    const infos = uiLogic.bluetoothDevices([root.bluetoothDeviceSummary(device, 0)])
    return infos.length > 0 ? infos[0] : null
  }

  function refreshBluetooth() {
    const availableDevices = root.adapterEnabled ? (root.devices || []) : []
    const list = root.sortedDevices(availableDevices.filter(device => root.deviceLabel(device).length > 0))
    root.deviceSnapshot = list

    root.connectedCount = 0
    root.connectedBattery = -1
    let hasAirpodsConnected = false

    const names = []
    for (let i = 0; i < list.length; i++) {
      const device = list[i]
      if (!device)
        continue
      if (device.connected) {
        root.connectedCount += 1
        const label = root.deviceLabel(device)
        if (label.length > 0)
          names.push(label)
        if (root.isAirpodsDevice(device))
          hasAirpodsConnected = true

        if (root.connectedBattery < 0)
          root.connectedBattery = root.deviceBatteryValue(device)
      }
    }

    if (hasAirpodsConnected && root.connectedBattery <= 0 && root.librepodsBattery > 0) {
      root.connectedBattery = root.librepodsBattery
      root.logDebug("using librepods battery fallback=" + root.librepodsBattery)
    }

    root.connectedNames = names.join(", ")

    if (root.pendingDeviceKey.length > 0) {
      const pendingStillExists = list.some(device => root.deviceKey(device) === root.pendingDeviceKey)
      if (!pendingStillExists)
        root.pendingDeviceKey = ""
    }

    root.updatePendingDeviceActions()
    root.requestScanState()
  }

  function toggleAdapterEnabled() {
    if (!root.adapter)
      return
    root.adapter.enabled = !root.adapter.enabled
    if (!root.adapter.enabled) {
      root.moduleScanSession = false
      root.desiredScanState = false
      root.scanActive = false
      root.pendingDeviceActions = ({})
      root.pendingDeviceKey = ""
      root.showUnpairedDevices = false
      root.refreshBluetooth()
    }
  }

  function setDiscovery(active) {
    if (!root.adapter || !root.adapterEnabled)
      return
    root.logDebug("setDiscovery(" + active + ") requested; adapterDiscovering=" + root.adapterDiscovering + " scanActive=" + root.scanActive + " desiredScanState=" + root.desiredScanState)
    root.lastScanAction = active ? "start" : "stop"
    root.desiredScanState = active
    root.moduleScanSession = active
    root.scanEnsureAttempts = 0;

    // Short-circuit only if both observed states already match the request.
    if (root.adapterDiscovering === active && root.scanActive === active) {
      root.scanActive = active
      root.logDebug("setDiscovery early-return (already in requested state)")
      scanEnsureTimer.stop()
      return
    }

    root.scanActive = active
    root.lastScanSource = "module"
    root.adapter.discovering = active
    root.logDebug("adapter.discovering set to " + active + "; now adapterDiscovering=" + root.adapterDiscovering)

    refreshTimer.restart()
    scanRefreshTimer.restart()
    scanEnsureTimer.start()
  }

  function toggleDiscovery() {
    const currentlyScanning = root.moduleScanSession || root.desiredScanState
    root.logDebug("toggleDiscovery currentlyScanning=" + currentlyScanning + " (moduleScanSession=" + root.moduleScanSession + ", desired=" + root.desiredScanState + ", scanActive=" + root.scanActive + ", adapterDiscovering=" + root.adapterDiscovering + ")")
    root.setDiscovery(!currentlyScanning)
  }

  function logDiscoveryOwner(context) {
    if (root.lastStartDiscoverySender.length === 0) {
      root.logDebug(context + " discovery owner unknown (no StartDiscovery sender seen)")
      bluetoothDiagnostics.probeScanHolders()
      return
    }
    root.logDebug(context + " possible holder sender=" + root.lastStartDiscoverySender + " pid=" + root.lastStartDiscoveryPid + " process=" + root.lastStartDiscoveryProcess)
    bluetoothDiagnostics.probeScanHolders()
  }

  function refreshBluetoothDiagnostics() {
    if (root.debugBluetooth && root.adapterEnabled) {
      bluetoothDiagnostics.startDiscoveryMonitor()
      bluetoothDiagnostics.probeLibrepodsTooltip()
    } else {
      bluetoothDiagnostics.stopDiscoveryMonitor()
    }
  }

  function notifyScanStopFailure() {
    const nowMs = Date.now()
    if (nowMs - root.lastScanStopNotifyMs < 15000)
      return
    root.lastScanStopNotifyMs = nowMs

    let detail = "Discovery appears to be owned by another process."
    if (root.lastScanHolders.length > 0) {
      const firstLine = root.lastScanHolders.split("\n")[0].trim()
      if (firstLine.length > 0)
        detail = "Possible holder: " + firstLine
    }

    Common.ProcessHelper.execDetached(["notify-send", "Bluetooth scan stop failed", detail])
  }

  function toggleDeviceConnection(device) {
    if (!device || !root.adapterEnabled)
      return
    const connectTarget = !device.connected
    root.beginPendingDeviceAction(device, connectTarget)

    try {
      if (connectTarget)
        device.connect()
      else
        device.disconnect()
    } catch (error) {
      root.clearPendingDeviceAction(root.deviceKey(device))
      root.notifyDeviceActionFailure(device, connectTarget, error)
    }

    refreshTimer.restart()
  }

  function deviceStateName(device) {
    if (!device || device.state === undefined)
      return ""

    return BluetoothDeviceState.toString(device.state)
  }

  function beginPendingDeviceAction(device, connectTarget) {
    const key = root.deviceKey(device)
    if (key.length === 0)
      return
    root.pendingDeviceKey = key
    root.pendingConnect = connectTarget

    const actions = Object.assign({}, root.pendingDeviceActions)
    actions[key] = {
      targetConnected: connectTarget,
      startedAt: Date.now(),
      label: root.deviceLabel(device) || root.adapterName,
      address: String(device.address || ""),
      startState: root.deviceStateName(device)
    }
    root.pendingDeviceActions = actions
    deviceActionTimer.restart()
  }

  function clearPendingDeviceAction(key) {
    const actions = Object.assign({}, root.pendingDeviceActions)
    if (!(key in actions))
      return
    delete actions[key]
    root.pendingDeviceActions = actions

    if (root.pendingDeviceKey === key)
      root.pendingDeviceKey = ""

    if (Object.keys(actions).length === 0)
      deviceActionTimer.stop()
  }

  function notifyDeviceActionFailure(device, connectTarget, error) {
    const label = root.deviceLabel(device) || root.adapterName
    const actionText = connectTarget ? "connect to" : "disconnect"
    let detail = "Bluetooth device did not " + actionText + " " + label + "."

    const errorText = String(error || "").trim()
    if (errorText.length > 0)
      detail += " " + errorText

    Common.ProcessHelper.execDetached(["notify-send", "Bluetooth action failed", detail])
  }

  function updatePendingDeviceActions() {
    const actions = root.pendingDeviceActions || {}
    const keys = Object.keys(actions)
    if (keys.length === 0) {
      deviceActionTimer.stop()
      return
    }

    const list = root.deviceSnapshot || []
    const now = Date.now()
    let hasPending = false

    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      const pending = actions[key]
      if (!pending)
        continue
      const device = list.find(candidate => root.deviceKey(candidate) === key)
      if (device) {
        const reachedTarget = pending.targetConnected ? !!device.connected : !device.connected
        if (reachedTarget) {
          root.clearPendingDeviceAction(key)
          continue
        }
      }

      if (now - pending.startedAt >= root.deviceActionTimeoutMs) {
        root.clearPendingDeviceAction(key)
        root.notifyDeviceActionFailure(device || {
          alias: pending.label,
          name: pending.label,
          address: pending.address
        }, pending.targetConnected, "")
        continue
      }

      hasPending = true
    }

    if (hasPending)
      deviceActionTimer.restart()
  }

  function openSettings() {
    Common.ProcessHelper.execDetached(root.onClickCommand)
  }

  Timer {
    id: refreshTimer
    interval: 1000
    repeat: false
    onTriggered: {
      root.pendingDeviceKey = ""
      root.refreshBluetooth()
    }
  }

  Timer {
    id: deviceActionTimer
    interval: 1000
    repeat: false
    onTriggered: root.updatePendingDeviceActions()
  }

  onDebugBluetoothChanged: root.refreshBluetoothDiagnostics()
  onAdapterEnabledChanged: root.refreshBluetoothDiagnostics()

  function requestScanState() {
    if (!root.adapterEnabled) {
      root.scanActive = false
      root.moduleScanSession = false
      root.desiredScanState = false
      root.logDebug("requestScanState skipped (adapter disabled)")
      return
    }
    root.scanActive = root.adapterDiscovering
    root.logDebug("requestScanState synced from adapter.discovering=" + root.scanActive)
    if (root.scanActive && !root.moduleScanSession && !root.desiredScanState)
      root.logDebug("scan appears to be held by another client/session")
  }

  Timer {
    id: librepodsProbeTimer
    interval: 10000
    repeat: true
    running: root.debugBluetooth
    triggeredOnStart: true
    onTriggered: bluetoothDiagnostics.probeLibrepodsTooltip()
  }

  Timer {
    id: scanPollTimer
    interval: 2000
    repeat: true
    running: root.tooltipActive && root.adapterEnabled
    onTriggered: {
      root.requestScanState()
    }
  }

  Timer {
    id: scanRefreshTimer
    interval: 500
    repeat: false
    onTriggered: root.requestScanState()
  }

  Timer {
    id: scanEnsureTimer
    interval: 1200
    repeat: true
    running: false
    onTriggered: {
      const adapterState = root.adapterDiscovering
      const uiState = root.scanActive
      const desired = root.desiredScanState
      const matches = (adapterState === desired && uiState === desired)

      root.logDebug("scanEnsure attempt=" + root.scanEnsureAttempts + " desired=" + desired + " adapterDiscovering=" + adapterState + " scanActive=" + uiState)

      if (matches || root.scanEnsureAttempts >= 3) {
        running = false
        root.requestScanState()
        if (!matches && !desired) {
          root.logDiscoveryOwner("scanEnsure exhausted;")
          root.notifyScanStopFailure()
        }
        return
      }

      root.scanEnsureAttempts += 1
      if (root.adapter && root.adapterEnabled)
        root.adapter.discovering = desired
      if (!desired)
        root.logDiscoveryOwner("scanEnsure retry;")
      root.requestScanState()
    }
  }

  IpcHandler {
    id: scanIpc
    target: "bluetooth-scan"

    function start() {
      root.lastScanSource = "ipc.start"
      root.setDiscovery(true)
    }

    function stop() {
      root.lastScanSource = "ipc.stop"
      root.setDiscovery(false)
    }

    function toggle() {
      root.lastScanSource = "ipc.toggle"
      root.toggleDiscovery()
    }

    function status() {
      return JSON.stringify({
        adapterEnabled: root.adapterEnabled,
        adapterId: root.adapter && root.adapter.adapterId ? String(root.adapter.adapterId) : "",
        adapterDiscovering: root.adapterDiscovering,
        scanActive: root.scanActive,
        moduleScanSession: root.moduleScanSession,
        desiredScanState: root.desiredScanState,
        scanEnsureAttempts: root.scanEnsureAttempts,
        lastScanSource: root.lastScanSource,
        lastScanAction: root.lastScanAction,
        lastStartDiscoverySender: root.lastStartDiscoverySender,
        lastStartDiscoveryPid: root.lastStartDiscoveryPid,
        lastStartDiscoveryProcess: root.lastStartDiscoveryProcess,
        lastScanHolders: root.lastScanHolders
      })
    }
  }

  tooltipHoverable: true
  tooltipText: ""
  tooltipTitle: root.connectedNames !== "" ? root.connectedNames : root.adapterName

  content: [
    IconLabel {
      color: root.stateColor()
      text: root.displayIcon()
    }
  ]

  tooltipContent: Component {
    ColumnLayout {
      id: menu

      readonly property int maxVisibleRows: 5
      readonly property int rowHeight: 46
      readonly property var pairedDevices: root.deviceSnapshot.filter(device => !!(device && device.paired))
      readonly property var unpairedDevices: root.deviceSnapshot.filter(device => !!(device && !device.paired))
      readonly property int pairedRowsShown: Math.min(maxVisibleRows, pairedDevices.length)
      readonly property int pairedRowsHeight: pairedRowsShown > 0 ? (pairedRowsShown * rowHeight) + ((pairedRowsShown - 1) * Config.space.xs) : 0
      readonly property int unpairedRowsShown: Math.min(maxVisibleRows, unpairedDevices.length)
      readonly property int unpairedRowsHeight: unpairedRowsShown > 0 ? (unpairedRowsShown * rowHeight) + ((unpairedRowsShown - 1) * Config.space.xs) : 0
      readonly property bool showDeviceLists: root.adapterEnabled && root.deviceSnapshot.length > 0

      spacing: Config.space.md
      width: 276

      RowLayout {
        id: headerRow

        Layout.fillWidth: true
        spacing: Config.space.md

        Item {
          Layout.preferredHeight: Config.space.xxl * 2
          Layout.preferredWidth: Config.space.xxl * 2

          Rectangle {
            anchors.centerIn: parent
            color: Qt.alpha(root.stateColor(), 0.12)
            height: parent.height
            radius: height / 2
            width: parent.width
          }

          Text {
            anchors.centerIn: parent
            color: root.stateColor()
            font.pixelSize: Config.type.headlineLarge.size
            text: root.displayIcon()
          }
        }

        Item {
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          implicitHeight: headerContent.implicitHeight

          ColumnLayout {
            id: headerContent
            anchors.fill: parent
            spacing: Config.space.none

            RowLayout {
              Layout.fillWidth: true
              spacing: Config.space.xs

              Text {
                Layout.minimumWidth: 0
                color: Config.color.on_surface
                elide: Text.ElideRight
                font.family: Config.fontFamily
                font.pixelSize: Config.type.headlineSmall.size
                font.weight: Font.Bold
                text: root.connectedNames !== "" ? root.connectedNames : root.adapterName
              }

              Text {
                color: Config.color.on_surface_variant
                font.family: Config.iconFontFamily
                font.pixelSize: Config.type.labelLarge.size
                text: root.detailsExpanded ? "󰅀" : "󰅂"
              }

              Item {
                Layout.fillWidth: true
              }
            }

            Text {
              Layout.fillWidth: true
              Layout.minimumWidth: 0
              color: Config.color.on_surface_variant
              elide: Text.ElideRight
              font.family: Config.fontFamily
              font.pixelSize: Config.type.labelMedium.size
              text: root.connectedBattery > 0 ? (root.statusLabel() + " • " + (root.librepodsBatterySummary().length > 0 ? root.librepodsBatterySummary() : (root.connectedBattery.toString() + "%"))) : root.statusLabel()
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.detailsExpanded = !root.detailsExpanded
          }
        }
      }

      ProgressBar {
        Layout.fillWidth: true
        Layout.preferredHeight: Config.space.xs
        fillColor: Config.color.tertiary
        trackColor: Config.color.surface_variant
        value: root.connectedBattery / 100
        visible: root.connectedBattery > 0
      }

      StackLayout {
        Layout.fillWidth: true
        currentIndex: root.detailsExpanded ? 1 : 0

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Config.space.xs

          RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: Config.space.xs
            spacing: Config.space.sm

            Text {
              color: Config.color.primary
              font.family: Config.fontFamily
              font.letterSpacing: 1.5
              font.pixelSize: Config.type.labelSmall.size
              font.weight: Font.Black
              text: "DEVICES"
            }

            Rectangle {
              Layout.alignment: Qt.AlignVCenter
              Layout.fillWidth: true
              color: Qt.alpha(Config.color.outline_variant, 0.55)
              implicitHeight: 1
              radius: 1
            }

            Item {
              Layout.fillHeight: true
              Layout.preferredWidth: toggleRow.implicitWidth + (Config.space.xs * 2)
              visible: root.adapterEnabled && menu.unpairedDevices.length > 0

              RowLayout {
                id: toggleRow
                anchors.centerIn: parent
                spacing: Config.space.xs

                Text {
                  color: Config.color.on_surface_variant
                  font.family: Config.fontFamily
                  font.pixelSize: Config.type.labelSmall.size
                  text: menu.unpairedDevices.length.toString()
                }

                Text {
                  color: Config.color.on_surface_variant
                  font.family: Config.iconFontFamily
                  font.pixelSize: Config.type.labelLarge.size
                  text: root.showUnpairedDevices ? "󰅀" : "󰅂"
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showUnpairedDevices = !root.showUnpairedDevices
              }
            }
          }

          Text {
            Layout.fillWidth: true
            color: Config.color.on_surface_variant
            font.family: Config.fontFamily
            font.pixelSize: Config.type.labelMedium.size
            text: !root.adapterEnabled ? "Turn Bluetooth on to discover and connect devices." : (root.moduleScanSession || root.desiredScanState ? "Scanning for devices. New devices will appear here." : "No Bluetooth devices available.")
            visible: !menu.showDeviceLists
            wrapMode: Text.Wrap
          }

          Item {
            Layout.fillWidth: true
            Layout.preferredHeight: menu.pairedRowsHeight
            clip: true
            visible: menu.showDeviceLists && menu.pairedRowsShown > 0

            ListView {
              anchors.fill: parent
              boundsBehavior: Flickable.StopAtBounds
              boundsMovement: Flickable.StopAtBounds
              clip: true
              flickableDirection: Flickable.VerticalFlick
              interactive: menu.pairedDevices.length > menu.maxVisibleRows
              model: menu.pairedDevices
              spacing: Config.space.xs
              delegate: BluetoothDeviceRow {
                moduleRoot: root
                rowHeight: menu.rowHeight
              }
            }
          }

          Item {
            Layout.fillWidth: true
            Layout.preferredHeight: menu.unpairedRowsHeight
            clip: true
            visible: menu.showDeviceLists && root.showUnpairedDevices && menu.unpairedRowsShown > 0

            ListView {
              anchors.fill: parent
              boundsBehavior: Flickable.StopAtBounds
              boundsMovement: Flickable.StopAtBounds
              clip: true
              flickableDirection: Flickable.VerticalFlick
              interactive: menu.unpairedDevices.length > menu.maxVisibleRows
              model: menu.unpairedDevices
              spacing: Config.space.xs
              delegate: BluetoothDeviceRow {
                moduleRoot: root
                rowHeight: menu.rowHeight
              }
            }
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Config.space.xs

          SectionHeader {
            text: "BLUETOOTH DETAILS"
          }

          InfoRow {
            Layout.fillWidth: true
            label: "Adapter"
            value: root.adapterName
          }

          InfoRow {
            Layout.fillWidth: true
            label: "Status"
            value: root.statusLabel()
          }

          InfoRow {
            Layout.fillWidth: true
            label: "Battery (L/R/C)"
            value: root.librepodsBatterySummary()
            visible: root.librepodsBatterySummary().length > 0
          }

          InfoRow {
            Layout.fillWidth: true
            label: "Scanning"
            value: root.scanActive ? "Yes" : "No"
            visible: !!root.adapter
          }

          InfoRow {
            Layout.fillWidth: true
            label: "Known Devices"
            value: root.adapterEnabled ? root.deviceSnapshot.length.toString() : "0"
            visible: !!root.adapter
          }
        }
      }

      TooltipActionsRow {
        spacing: Config.space.sm

        ActionChip {
          Layout.fillWidth: true
          text: root.adapterEnabled ? "Turn Off" : "Turn On"
          onClicked: root.toggleAdapterEnabled()
        }

        ActionChip {
          Layout.fillWidth: true
          enabled: root.adapterEnabled
          text: (root.moduleScanSession || root.desiredScanState) ? "Stop Scan" : "Scan"
          onClicked: scanIpc.toggle()
        }
      }

      TooltipActionsRow {
        spacing: Config.space.sm

        ActionChip {
          Layout.fillWidth: true
          text: "Open Settings"
          onClicked: root.openSettings()
        }

        ActionChip {
          Layout.fillWidth: true
          text: "Refresh"
          onClicked: root.refreshBluetooth()
        }
      }
    }
  }

  onAdapterChanged: root.refreshBluetooth()
  onDevicesChanged: root.refreshBluetooth()
  onAdapterDiscoveringChanged: {
    root.logDebug("onAdapterDiscoveringChanged -> " + root.adapterDiscovering)
    root.scanActive = root.adapterDiscovering
    root.requestScanState()
  }
  onTooltipActiveChanged: {
    if (root.tooltipActive) {
      root.refreshBluetooth()
      root.requestScanState()
    }
  }

  onClicked: root.openSettings()

  Component.onCompleted: root.refreshBluetooth()
}
