pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qscapture 1.0

import "src" as Src
import "src/ScreenshotUtils.js" as ScreenshotUtils
import "ui" as Ui
import "common" as Common
import "../common" as SharedCommon
import "../common/JsonUtils.js" as JsonUtils

Src.FreezeScreen {
  id: root

  readonly property int countdownStartValue: 3
  readonly property int countdownTickMs: 900
  readonly property int grabDelayMs: 60
  property bool active: false
  property var activeScreen: null
  property bool awaitingScreenConfirm: false
  property var countdownCenter: Qt.point(width / 2, height / 2)
  property int countdownValue: root.countdownStartValue
  property bool grabReady: false
  property var hyprlandMonitor: root.active ? (activeScreen ? Hyprland.monitorFor(activeScreen) : Hyprland.focusedMonitor) : null
  property string lastScreenshotPath: ""
  property bool lastScreenshotTemporary: false
  property string mode: "region"
  readonly property var colors: Common.Config.color
  property string currentRecordingAudioDevice: ""
  property string currentRecordingPath: ""
  readonly property string recordFlagPath: runtimeDir ? `${runtimeDir}/hyprquickshot-recording` : ""
  property string _recordAudioMode: "monitor"
  readonly property string recordAudioMode: root._recordAudioMode
  property bool recordMode: recordingState !== "idle" || recordProcess.running
  property var pendingRecordingPlan: null
  property var recordingSelection: null
  property string recordingState: "idle"
  property var regionSelectorItem: regionSelectorLoader.item
  property bool _saveToDisk: true
  readonly property bool saveToDisk: root._saveToDisk
  property bool settingsLoaded: false
  readonly property string settingsPath: Quickshell.shellPath("data/hyprquickshot.conf")
  property bool sessionVisible: false
  property bool screenshotFailureKeepsSession: false
  property string tempPath
  property bool wlScreenrecAvailable: false
  property bool pactlAvailable: false
  property string frozenWindowCacheState: "idle"
  property var frozenWindowTargets: []
  property bool frozenWindowToplevelRefreshPending: false
  property string initialGrabRequestId: ""
  property string frozenWindowCacheRequestId: ""
  property string screenshotRequestId: ""
  property var debugCaptureRequests: ({})
  property var debugEventHistory: []
  property var windowSelectorItem: windowSelectorLoader.item
  readonly property var allHyprlandToplevels: root.active && Hyprland.toplevels && Hyprland.toplevels.values ? Hyprland.toplevels.values : []
  readonly property var workspaceToplevels: root.active ? root.filterWorkspaceToplevels(root.allHyprlandToplevels, root.hyprlandMonitor) : []
  readonly property var liveWindowTargets: root.buildWindowTargets(root.workspaceToplevels, root.hyprlandMonitor, false)
  readonly property var currentWindowTargets: root.screenFrozen ? root.frozenWindowTargets : root.liveWindowTargets
  readonly property bool windowModeLoading: root.screenFrozen && (root.initialFrozenGrabPending || root.frozenWindowCacheState === "capturing")
  readonly property bool windowModeAvailable: root.currentWindowTargets.length > 0

  function createRequestId(prefix) {
    return `${prefix}-${Date.now()}-${Math.round(Math.random() * 100000)}`
  }
  function normalizeRecordAudioMode(modeValue) {
    return modeValue === "defaultMic" || modeValue === "off" ? modeValue : "monitor"
  }
  function loadSettings() {
    const data = JsonUtils.parseObject(settingsFile.text())
    if (data) {
      if (typeof data.saveToDisk === "boolean")
        root._saveToDisk = data.saveToDisk
      if (typeof data.recordAudioMode === "string")
        root._recordAudioMode = root.normalizeRecordAudioMode(data.recordAudioMode)
    }
    root.settingsLoaded = true
  }
  function saveSettings() {
    if (!root.settingsLoaded)
      return
    settingsFile.setText(JSON.stringify({
      saveToDisk: root._saveToDisk,
      recordAudioMode: root._recordAudioMode
    }))
  }
  function resolveScreenshotOutput() {
    return ScreenshotUtils.resolveScreenshotOutput({
      env: root.environment(),
      now: new Date(),
      saveToDisk: root.saveToDisk
    })
  }
  function beginScreenshotCapture(requestId, output) {
    root.screenshotRequestId = requestId
    root.lastScreenshotTemporary = !!output.temporary
    root.lastScreenshotPath = String(output.outputPath || "")
    root.sessionVisible = false
  }

  function asList(value) {
    if (!value)
      return []
    if (Array.isArray(value))
      return value
    if (value.length !== undefined) {
      const list = []
      for (let index = 0; index < Number(value.length); index += 1)
        list.push(value[index])
      return list
    }
    return []
  }
  function monitorIpcObject(monitor) {
    return monitor && monitor.lastIpcObject ? monitor.lastIpcObject : null
  }
  function selectedWorkspaceForMonitor(monitor) {
    const monitorObject = root.monitorIpcObject(monitor)
    const specialWorkspace = monitorObject && monitorObject.specialWorkspace ? monitorObject.specialWorkspace : (monitor && monitor.specialWorkspace ? monitor.specialWorkspace : null)
    const specialWorkspaceName = specialWorkspace ? String(specialWorkspace.name || "") : ""
    if (specialWorkspaceName !== "")
      return specialWorkspace
    return monitor && monitor.activeWorkspace ? monitor.activeWorkspace : null
  }
  function workspaceMatches(workspace, selectedWorkspace) {
    if (!workspace || !selectedWorkspace)
      return false

    const workspaceName = String(workspace.name || "")
    const selectedWorkspaceName = String(selectedWorkspace.name || "")
    if (selectedWorkspaceName !== "")
      return workspaceName === selectedWorkspaceName

    const workspaceId = workspace.id !== undefined ? Number(workspace.id) : NaN
    const selectedWorkspaceId = selectedWorkspace.id !== undefined ? Number(selectedWorkspace.id) : NaN
    return !isNaN(workspaceId) && !isNaN(selectedWorkspaceId) && workspaceId === selectedWorkspaceId
  }
  function filterWorkspaceToplevels(toplevels, monitor) {
    const source = root.asList(toplevels)
    const selectedWorkspace = root.selectedWorkspaceForMonitor(monitor)
    const monitorName = monitor ? String(monitor.name || "") : ""
    const monitorObject = root.monitorIpcObject(monitor)
    const filtered = []

    for (const toplevel of source) {
      const workspace = toplevel && toplevel.workspace ? toplevel.workspace : null
      const workspaceMonitor = workspace && workspace.monitor ? workspace.monitor : null
      const screens = toplevel && toplevel.screens ? root.asList(toplevel.screens) : []
      const screenMatches = screens.length === 0 ? true : screens.some(screen => screen && String(screen.name || "") === monitorName)
      const ipcObject = toplevel && toplevel.lastIpcObject ? toplevel.lastIpcObject : null
      const toplevelMonitor = ipcObject && ipcObject.monitor !== undefined ? Number(ipcObject.monitor) : null
      const monitorMatches = !monitorName ? true : ((workspaceMonitor && String(workspaceMonitor.name || "") === monitorName) || screenMatches || (!workspaceMonitor && monitorObject && toplevelMonitor === Number(monitorObject.id)))

      if (monitorMatches && root.workspaceMatches(workspace, selectedWorkspace))
        filtered.push(toplevel)
    }

    return filtered
  }
  function refreshLiveWindowTargets() {
    if (!root.active || !root.sessionVisible || root.mode !== "window" || root.screenFrozen)
      return
    Hyprland.refreshMonitors()
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
  }
  function buildWindowTarget(toplevel, monitor, frozen) {
    const monitorObject = monitor && monitor.lastIpcObject ? monitor.lastIpcObject : null
    const ipcObject = toplevel && toplevel.lastIpcObject ? toplevel.lastIpcObject : null
    const stableId = ipcObject && ipcObject.stableId ? String(ipcObject.stableId) : ""
    if (!ipcObject || ipcObject.mapped === false || ipcObject.hidden || !ipcObject.at || !ipcObject.size || stableId === "")
      return null

    const token = `${Date.now()}-${Math.round(Math.random() * 100000)}`
    const activeScreen = root.activeScreen || null
    const monitorOffsetX = monitorObject && monitorObject.x !== undefined ? Number(monitorObject.x) : Number(activeScreen ? activeScreen.x || 0 : 0)
    const monitorOffsetY = monitorObject && monitorObject.y !== undefined ? Number(monitorObject.y) : Number(activeScreen ? activeScreen.y || 0 : 0)
    return {
      stableId: stableId,
      x: Number(ipcObject.at[0]) - monitorOffsetX,
      y: Number(ipcObject.at[1]) - monitorOffsetY,
      width: Number(ipcObject.size[0]),
      height: Number(ipcObject.size[1]),
      title: String(ipcObject.title || ""),
      className: String(ipcObject.class || ""),
      captureState: frozen ? "pending" : "ready",
      imagePath: frozen ? Quickshell.cachePath(`hyprquickshot-window-${token}-${stableId}.png`) : ""
    }
  }
  function buildWindowTargets(toplevels, monitor, frozen) {
    const targets = []
    const source = root.asList(toplevels)
    const workspace = root.selectedWorkspaceForMonitor(monitor)

    console.log("[window-targets] build start", "frozen=", frozen, "monitor=", monitor ? monitor.name : "null", "workspace=", workspace ? workspace.name : "null", "sourceCount=", source.length)

    for (const toplevel of source) {
      const target = root.buildWindowTarget(toplevel, monitor, frozen)
      if (target)
        targets.push(target)
    }

    console.log("[window-targets] build complete", "frozen=", frozen, "targetCount=", targets.length, "stableIds=", JSON.stringify(targets.map(target => target.stableId)))
    return targets
  }
  function findCurrentWindowTarget(stableId) {
    const targetId = String(stableId || "")
    const targets = Array.isArray(root.currentWindowTargets) ? root.currentWindowTargets : []
    for (const target of targets) {
      if (target && String(target.stableId || "") === targetId)
        return target
    }
    return null
  }
  function updateDebugCapture(requestId, values) {
    const next = Object.assign({}, root.debugCaptureRequests)
    const current = Object.assign({}, next[requestId] || {})
    next[requestId] = Object.assign(current, values || {})
    root.debugCaptureRequests = next
  }
  function appendDebugEvent(eventName, payload) {
    const next = Array.isArray(root.debugEventHistory) ? root.debugEventHistory.slice(0) : []
    next.push({
      event: String(eventName || ""),
      payload: payload || {},
      timestamp: Date.now()
    })
    while (next.length > 60)
      next.shift()
    root.debugEventHistory = next
  }
  function debugCaptureStatusJson() {
    return JSON.stringify(root.debugCaptureRequests)
  }
  function debugStateJson() {
    return JSON.stringify({
      active: root.active,
      activeScreen: root.activeScreen ? {
        name: root.activeScreen.name || "",
        width: Number(root.activeScreen.width || 0),
        height: Number(root.activeScreen.height || 0),
        x: Number(root.activeScreen.x || 0),
        y: Number(root.activeScreen.y || 0)
      } : null,
      currentWindowTargets: root.currentWindowTargets,
      hyprlandMonitor: root.hyprlandMonitor ? {
        name: root.hyprlandMonitor.name || "",
        width: Number(root.hyprlandMonitor.width || 0),
        height: Number(root.hyprlandMonitor.height || 0),
        x: Number(root.hyprlandMonitor.x || 0),
        y: Number(root.hyprlandMonitor.y || 0)
      } : null,
      mode: root.mode,
      allHyprlandToplevelCount: root.asList(root.allHyprlandToplevels).length,
      frozenWindowToplevelRefreshPending: root.frozenWindowToplevelRefreshPending,
      frozenWindowCacheState: root.frozenWindowCacheState,
      frozenWindowTargets: root.frozenWindowTargets,
      pendingFreezeFilePath: root.runtimeDir ? `${root.runtimeDir}/hyprquickshot_frozen_${root.targetScreen ? root.targetScreen.name || "" : ""}.png` : "",
      recordingState: root.recordingState,
      screenFrozen: root.screenFrozen,
      sessionVisible: root.sessionVisible,
      workspaceToplevels: root.buildWindowTargets(root.workspaceToplevels, root.hyprlandMonitor, false),
      windowModeAvailable: root.windowModeAvailable,
      windowModeLoading: root.windowModeLoading,
      debugEventHistory: root.debugEventHistory
    })
  }
  function debugSetMode(modeValue) {
    const nextMode = String(modeValue || "")
    if (nextMode !== "region" && nextMode !== "window" && nextMode !== "screen")
      return false
    root.setMode(nextMode)
    return true
  }
  function debugRefreshWindows() {
    Hyprland.refreshMonitors()
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    Qt.callLater(root.syncSelectorPreview)
    return root.debugStateJson()
  }
  function debugCaptureWindow(stableId) {
    const targetId = String(stableId || "")
    if (targetId === "")
      return ""
    const target = root.findCurrentWindowTarget(targetId)
    const outputPath = Quickshell.cachePath(`hyprquickshot-debug-window-${targetId}-${Date.now()}.png`)
    const requestId = root.createRequestId("debug-window-capture")
    root.updateDebugCapture(requestId, {
      outputPath: outputPath,
      stableId: targetId,
      startedAt: Date.now(),
      status: "pending",
      target: target ? {
        x: Number(target.x || 0),
        y: Number(target.y || 0),
        width: Number(target.width || 0),
        height: Number(target.height || 0),
        title: String(target.title || ""),
        className: String(target.className || "")
      } : null
    })
    captureProvider.captureToplevel(requestId, targetId, outputPath, false)
    return requestId
  }
  function cleanupFrozenWindowCache() {
    console.log("[window-targets] cleanup frozen cache", "requestId=", root.frozenWindowCacheRequestId, "targetCount=", root.frozenWindowTargets.length)
    root.frozenWindowCacheRequestId = ""

    const targets = Array.isArray(root.frozenWindowTargets) ? root.frozenWindowTargets : []
    const paths = []

    for (const target of targets) {
      const imagePath = target && target.imagePath ? String(target.imagePath) : ""
      if (imagePath !== "")
        paths.push(imagePath)
    }

    if (paths.length > 0) {
      const command = ["rm", "-f", "--"]
      for (const path of paths)
        command.push(path)
      Quickshell.execDetached(command)
    }

    root.frozenWindowTargets = []
    root.frozenWindowCacheState = "idle"
  }
  function launchFrozenWindowCacheBatch(targets) {
    root.appendDebugEvent("launchFrozenWindowCacheBatch", {
      targetCount: Array.isArray(targets) ? targets.length : 0,
      stableIds: Array.isArray(targets) ? targets.map(target => String(target.stableId || "")) : []
    })
    root.cleanupFrozenWindowCache()
    root.frozenWindowTargets = Array.isArray(targets) ? targets : []
    root.frozenWindowCacheState = root.frozenWindowTargets.length > 0 ? "capturing" : "ready"
    console.log("[window-targets] frozen cache start", "state=", root.frozenWindowCacheState, "count=", root.frozenWindowTargets.length)
    if (root.frozenWindowTargets.length === 0) {
      Qt.callLater(root.syncSelectorPreview)
      return
    }

    const requests = []
    for (const target of root.frozenWindowTargets)
      requests.push({
        identifier: target.stableId,
        filePath: target.imagePath
      })
    root.frozenWindowCacheRequestId = root.createRequestId("frozen-window-cache")
    console.log("[window-targets] launching frozen cache capture", "requestId=", root.frozenWindowCacheRequestId)
    captureProvider.captureToplevelBatch(root.frozenWindowCacheRequestId, requests, false)
  }
  function startFrozenWindowCacheCapture() {
    if (!root.active || !root.screenFrozen || root.frozenFrame === "") {
      root.appendDebugEvent("startFrozenWindowCacheCapture:skipped", {
        active: root.active,
        screenFrozen: root.screenFrozen,
        frozenFrame: String(root.frozenFrame || "")
      })
      return
    }
    root.frozenWindowCacheState = "capturing"
    const targets = root.buildWindowTargets(root.workspaceToplevels, root.hyprlandMonitor, true)
    root.appendDebugEvent("startFrozenWindowCacheCapture:evaluated", {
      targetCount: targets.length,
      stableIds: targets.map(target => String(target.stableId || "")),
      allHyprlandToplevelCount: root.asList(root.allHyprlandToplevels).length,
      frozenFrame: String(root.frozenFrame || "")
    })
    if (targets.length === 0 && !root.frozenWindowToplevelRefreshPending) {
      root.frozenWindowToplevelRefreshPending = true
      root.appendDebugEvent("startFrozenWindowCacheCapture:pendingRefresh", {
        allHyprlandToplevelCount: root.asList(root.allHyprlandToplevels).length
      })
      Hyprland.refreshMonitors()
      Hyprland.refreshWorkspaces()
      Hyprland.refreshToplevels()
      frozenWindowToplevelRetry.restart()
      return
    }
    root.frozenWindowToplevelRefreshPending = false
    frozenWindowToplevelRetry.stop()
    root.launchFrozenWindowCacheBatch(targets)
  }
  function syncSelectorPreview() {
    if (!sessionVisible || initialFrozenGrabPending)
      return
    if (mode === "window" && !windowModeAvailable) {
      resetSelectionState()
      return
    }
    if (awaitingScreenConfirm) {
      if (regionSelectorItem && typeof regionSelectorItem.setSelectionRect === "function")
        regionSelectorItem.setSelectionRect(0, 0, regionSelectorItem.width, regionSelectorItem.height)
      return
    }
    if (mode === "window" && windowSelectorItem && typeof windowSelectorItem.refreshHover === "function") {
      windowSelectorItem.refreshHover()
      return
    }
    resetSelectionState()
  }
  function syncGlobalState() {
    SharedCommon.GlobalState.screenRecordingActive = recordProcess.running
    SharedCommon.GlobalState.screenRecordingAudioDevice = currentRecordingAudioDevice
    SharedCommon.GlobalState.screenRecordingAudioMode = recordAudioMode
    SharedCommon.GlobalState.screenRecordingPath = currentRecordingPath
    SharedCommon.GlobalState.screenRecordingPid = recordProcess.processId === null || recordProcess.processId === undefined ? 0 : Number(recordProcess.processId)
    SharedCommon.GlobalState.screenRecordingState = recordingState
  }
  function activate() {
    if (recordProcess.running) {
      stopActiveRecording()
      return
    }
    active = true
    sessionVisible = false
    grabReady = false
    screenFrozen = true
    resetSessionState()
    resetSelectionState()
    grabDelay.restart()
  }
  function beginCountdownForSelection(sel) {
    if (!sel || sel.width <= 0 || sel.height <= 0) {
      stopRecordFlow()
      return
    }
    recordingSelection = sel
    countdownCenter = Qt.point(sel.x + sel.width / 2, sel.y + sel.height / 2)
    recordingState = "countdown"
    countdownValue = root.countdownStartValue
    countdownOverlay.pulse()
    countdownTimer.start()
  }
  function cleanupTempPath() {
    if (!tempPath || tempPath === "")
      return
    Quickshell.execDetached(["rm", "-f", tempPath])
  }
  function clearRecordFlag() {
    if (!recordFlagPath)
      return
    Quickshell.execDetached(["rm", "-f", "--", recordFlagPath])
  }
  function clearRecordingMetadata() {
    currentRecordingAudioDevice = ""
    currentRecordingPath = ""
  }
  function environment() {
    return {
      HOME: Quickshell.env("HOME") || "",
      HQS_DIR: Quickshell.env("HQS_DIR") || "",
      XDG_SCREENSHOTS_DIR: Quickshell.env("XDG_SCREENSHOTS_DIR") || "",
      XDG_PICTURES_DIR: Quickshell.env("XDG_PICTURES_DIR") || "",
      XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR") || ""
    }
  }
  function deactivate() {
    if (!active && !sessionVisible)
      return
    if (recordProcess.running) {
      stopActiveRecording()
      return
    }
    active = false
    if (SharedCommon.GlobalState.hyprQuickshotVisible)
      SharedCommon.GlobalState.hyprQuickshotVisible = false
    sessionVisible = false
    grabReady = false
    screenshotFailureKeepsSession = false
    grabDelay.stop()
    resetSessionState()
  }
  function notifyRecordingFailure(reason) {
    Quickshell.execDetached(["notify-send", "-a", "HyprShot", "Recording failed", reason])
  }
  function notifyRecordingSuccess() {
    if (!currentRecordingPath || currentRecordingPath === "")
      return
    Quickshell.execDetached(["notify-send", "-a", "HyprShot", "Recording saved", currentRecordingPath])
  }
  function notifyScreenshotSuccess() {
    if (!lastScreenshotPath || lastScreenshotPath === "")
      return
    const summary = root.saveToDisk ? "Screenshot saved" : "Screenshot copied"
    const body = root.saveToDisk ? lastScreenshotPath : "Copied to clipboard"
    const scriptPath = Quickshell.shellPath("hyprquickshot/scripts/notify-screenshot.sh")
    if (scriptPath && scriptPath !== "") {
      Quickshell.execDetached([scriptPath, summary, body, lastScreenshotPath])
    } else {
      Quickshell.execDetached(["notify-send", "-a", "HyprShot", summary, body])
    }
  }
  function processScreenshot(x, y, width, height) {
    if (!root.active || width <= 0 || height <= 0)
      return
    resetSelectionState()

    const screen = root.targetScreen
    if (!screen)
      return
    const output = root.resolveScreenshotOutput()
    const requestId = root.createRequestId("screenshot")
    root.screenshotFailureKeepsSession = false
    root.beginScreenshotCapture(requestId, output)

    if (root.screenFrozen) {
      const sourcePath = ScreenshotUtils.stripFileUrl(root.frozenFrame)
      const fullScreenSelection = x === 0 && y === 0 && width === screen.width && height === screen.height
      if (fullScreenSelection)
        captureProvider.copyImageFile(requestId, sourcePath, output.outputPath)
      else
        captureProvider.cropImageFile(requestId, sourcePath, x, y, width, height, hyprlandMonitor && hyprlandMonitor.scale !== undefined ? hyprlandMonitor.scale : 1, output.outputPath)
      return
    }

    const fullScreenSelection = x === 0 && y === 0 && width === screen.width && height === screen.height
    if (fullScreenSelection)
      captureProvider.captureOutput(requestId, screen.name || (hyprlandMonitor ? hyprlandMonitor.name : ""), output.outputPath, false)
    else
      captureProvider.captureRegion(requestId, screen.x + x, screen.y + y, width, height, output.outputPath, hyprlandMonitor && hyprlandMonitor.scale !== undefined ? hyprlandMonitor.scale : 1, false)
  }
  function processWindowScreenshot(target) {
    if (!root.active || !target || !target.stableId)
      return
    resetSelectionState()

    const output = root.resolveScreenshotOutput()
    const requestId = root.createRequestId("window-screenshot")
    if (root.screenFrozen) {
      if (root.windowModeLoading || target.captureState !== "ready" || !target.imagePath)
        return
      root.screenshotFailureKeepsSession = true
      root.beginScreenshotCapture(requestId, output)
      captureProvider.copyImageFile(requestId, target.imagePath, output.outputPath)
    } else {
      root.screenshotFailureKeepsSession = true
      root.beginScreenshotCapture(requestId, output)
      captureProvider.captureToplevel(requestId, target.stableId, output.outputPath, false)
    }
  }
  function toggleSaveMode() {
    if (recordingState === "countdown" || recordingState === "recording")
      return
    root.setSaveToDisk(!root.saveToDisk)
  }
  function setSaveToDisk(value) {
    root._saveToDisk = !!value
    root.saveSettings()
  }
  function resetSelectionState() {
    if (regionSelectorItem && typeof regionSelectorItem.resetSelection === "function")
      regionSelectorItem.resetSelection()
    if (windowSelectorItem && typeof windowSelectorItem.resetSelection === "function")
      windowSelectorItem.resetSelection()
  }
  function setRecordAudioMode(modeValue) {
    root._recordAudioMode = root.normalizeRecordAudioMode(modeValue)
    root.saveSettings()
  }
  function isPreRecordState() {
    return recordingState === "selecting" || recordingState === "countdown"
  }
  function cancelRecordFlowToScreenshot() {
    if (!root.isPreRecordState())
      return
    root.stopRecordFlow()
    if (root.mode === "screen")
      root.awaitingScreenConfirm = true
    if (root.active && root.sessionVisible)
      Qt.callLater(root.syncSelectorPreview)
  }
  function setMode(newMode) {
    if (recordingState === "recording")
      return
    const cancellingPreRecord = root.isPreRecordState()
    if (cancellingPreRecord)
      root.stopRecordFlow()

    if (mode === newMode && !cancellingPreRecord)
      return
    mode = newMode
    if (newMode === "window") {
      Hyprland.refreshMonitors()
      Hyprland.refreshWorkspaces()
      Hyprland.refreshToplevels()
      root.refreshLiveWindowTargets()
    }
    awaitingScreenConfirm = newMode === "screen"
    Qt.callLater(root.syncSelectorPreview)
  }
  function toggleMode() {
    const cycle = ["window", "screen", "region"]
    const index = cycle.indexOf(mode)
    for (let offset = 1; offset <= cycle.length; offset += 1) {
      const nextMode = cycle[(index + offset) % cycle.length]
      setMode(nextMode)
      return
    }
  }
  function resetSessionState() {
    countdownTimer.stop()
    countdownValue = root.countdownStartValue
    recordingState = "idle"
    recordingSelection = null
    awaitingScreenConfirm = false
    mode = "region"
    activeScreen = null
    sessionVisible = false
    screenshotFailureKeepsSession = false
    frozenWindowToplevelRefreshPending = false
    initialGrabRequestId = ""
    screenshotRequestId = ""
    frozenWindowCacheRequestId = ""
    syncRecordFlag()
    cleanupTempPath()
    cleanupFrozenWindowCache()
    clearRecordingMetadata()
    resetSelectionState()
    frozenFrame = ""
    frozenFrameAttempts = 0
    initialFrozenGrabPending = true
    surfaceTransparencyActive = false
  }
  function selectFocusedMonitorAndGrab() {
    const preferredScreen = SharedCommon.GlobalState.hyprQuickshotScreen
    const monitor = Hyprland.focusedMonitor
    let selectedScreen = null
    if (preferredScreen)
      selectedScreen = preferredScreen
    if (!selectedScreen && monitor) {
      for (const screen of Quickshell.screens) {
        if (screen.name === monitor.name) {
          selectedScreen = screen
          break
        }
      }
    }
    if (!selectedScreen && Quickshell.screens.length > 0)
      selectedScreen = Quickshell.screens[0]
    if (!selectedScreen)
      return
    SharedCommon.GlobalState.hyprQuickshotScreen = selectedScreen
    root.activeScreen = selectedScreen
    root.abortPendingInternalCapture("hyprquickshot-selectFocusedMonitorAndGrab")
    const timestamp = Date.now()
    const path = Quickshell.cachePath(`screenshot-${timestamp}.png`)
    root.tempPath = path
    root.initialGrabRequestId = root.createRequestId("initial-freeze")
    captureProvider.captureOutput(root.initialGrabRequestId, selectedScreen.name, path, false)
  }
  function startRecordFlow() {
    if (recordingState !== "idle")
      return
    if (!wlScreenrecAvailable) {
      notifyRecordingFailure("wl-screenrec is not available")
      return
    }
    if ((recordAudioMode === "monitor" || recordAudioMode === "defaultMic") && !pactlAvailable) {
      notifyRecordingFailure("pactl is required to resolve the selected audio source")
      return
    }
    recordingSelection = null
    recordingState = "selecting"
    awaitingScreenConfirm = mode === "screen"
  }
  function startRecording(selection) {
    if (!selection || selection.width <= 0 || selection.height <= 0) {
      stopRecordFlow()
      return
    }
    // Quickshell handles capture/view state here, but recording still relies
    // on wl-screenrec plus pactl for audio source selection.
    const plan = ScreenshotUtils.planRecording({
      audioMode: root.recordAudioMode,
      env: {
        HOME: Quickshell.env("HOME") || "",
        XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR") || "",
        XDG_VIDEOS_DIR: Quickshell.env("XDG_VIDEOS_DIR") || ""
      },
      mode: root.mode,
      now: new Date(),
      targetScreen: root.targetScreen,
      x: selection.x,
      y: selection.y,
      width: selection.width,
      height: selection.height
    })
    root.pendingRecordingPlan = plan
    currentRecordingPath = plan.outputPath
    currentRecordingAudioDevice = plan.audioDevice || (root.recordAudioMode === "monitor" ? "default monitor" : (root.recordAudioMode === "defaultMic" ? "default mic" : ""))
    recordingState = "recording"
    sessionVisible = false
    awaitingScreenConfirm = false
    recordingSelection = selection
    recordDirectoryProcess.command = ["mkdir", "-p", "--", plan.outputDir]
    recordDirectoryProcess.running = false
    recordDirectoryProcess.running = true
  }
  function launchRecordingPlan(plan) {
    if (!plan || !plan.command || plan.command.length === 0) {
      notifyRecordingFailure("Recording command could not be prepared")
      stopRecordFlow()
      return
    }
    currentRecordingPath = plan.outputPath
    currentRecordingAudioDevice = plan.audioDevice || (root.recordAudioMode === "monitor" ? "default monitor" : (root.recordAudioMode === "defaultMic" ? "default mic" : ""))
    recordProcess.command = plan.command
    recordProcess.running = false
    recordProcess.running = true
  }
  function stopRecordFlow() {
    countdownTimer.stop()
    countdownValue = root.countdownStartValue
    pendingRecordingPlan = null
    recordingState = "idle"
    recordingSelection = null
    awaitingScreenConfirm = false
  }
  function toggleRecordFlow() {
    if (root.recordingState === "idle") {
      root.startRecordFlow()
      return
    }
    if (root.isPreRecordState())
      root.cancelRecordFlowToScreenshot()
  }
  function stopActiveRecording() {
    countdownTimer.stop()
    if (recordProcess.running) {
      recordProcess.signal(2)
      return
    }
    stopRecordFlow()
  }
  function syncRecordFlag() {
    if (recordProcess.running || recordingState === "recording")
      writeRecordFlag()
    else
      clearRecordFlag()
  }
  function toggleActive() {
    if (active)
      deactivate()
    else
      activate()
  }
  function writeRecordFlag() {
    if (!recordFlagPath)
      return
    Quickshell.execDetached(["touch", "--", recordFlagPath])
  }

  freezeOpacity: recordingState === "recording" ? 0.0 : 1.0
  captureProvider: captureProvider
  keyboardFocusMode: recordingState === "recording" ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand
  mask: recordingState === "recording" ? emptyMask : fullMask
  screenFrozen: false
  targetScreen: activeScreen
  visible: active && sessionVisible

  Component.onCompleted: {
    root.loadSettings()
    SharedCommon.GlobalState.registerHyprQuickshot(root)
    Common.DependencyCheck.require("wl-screenrec", "HyprQuickshot", function (available) {
      root.wlScreenrecAvailable = available
    })
    Common.DependencyCheck.require("pactl", "HyprQuickshot", function (available) {
      root.pactlAvailable = available
    })
    if (SharedCommon.GlobalState.hyprQuickshotVisible)
      activate()
    root.syncGlobalState()
  }
  Connections {
    target: SharedCommon.GlobalState
    function onHyprQuickshotVisibleChanged() {
      if (SharedCommon.GlobalState.hyprQuickshotVisible) {
        if (!root.active)
          root.activate()
      } else if (root.active && !recordProcess.running) {
        root.deactivate()
      }
    }
  }
  Component.onDestruction: {
    if (SharedCommon.GlobalState.hyprQuickshotController === root)
      SharedCommon.GlobalState.registerHyprQuickshot(null)
    SharedCommon.GlobalState.hyprQuickshotVisible = false
    SharedCommon.GlobalState.resetScreenRecordingState()
  }
  onActiveChanged: {
    if (root.active) {
      Hyprland.refreshMonitors()
      Hyprland.refreshWorkspaces()
      Hyprland.refreshToplevels()
    }
    root.syncGlobalState()
    root.appendDebugEvent("activeChanged", {
      active: root.active
    })
  }
  onCurrentRecordingAudioDeviceChanged: root.syncGlobalState()
  onCurrentRecordingPathChanged: root.syncGlobalState()
  onRecordAudioModeChanged: root.syncGlobalState()
  onRecordingStateChanged: {
    syncRecordFlag()
    root.syncGlobalState()
    root.appendDebugEvent("recordingStateChanged", {
      recordingState: root.recordingState
    })
  }
  onFrozenFrameChanged: {
    root.appendDebugEvent("frozenFrameChanged", {
      frozenFrame: String(root.frozenFrame || "")
    })
    if (root.screenFrozen && root.frozenFrame !== "")
      root.startFrozenWindowCacheCapture()
    else if (!root.screenFrozen)
      root.cleanupFrozenWindowCache()
  }
  onFrozenWindowCacheStateChanged: Qt.callLater(root.syncSelectorPreview)
  onCurrentWindowTargetsChanged: {
    console.log("[window-targets] current targets changed", "mode=", root.mode, "screenFrozen=", root.screenFrozen, "loading=", root.windowModeLoading, "count=", root.currentWindowTargets.length)
    root.appendDebugEvent("currentWindowTargetsChanged", {
      count: root.currentWindowTargets.length,
      mode: root.mode,
      screenFrozen: root.screenFrozen,
      windowModeLoading: root.windowModeLoading
    })
    if (root.mode === "window" && root.sessionVisible && !root.windowModeLoading)
      Qt.callLater(root.syncSelectorPreview)
    if (!root.windowModeLoading && !root.windowModeAvailable)
      root.resetSelectionState()
  }
  onSessionVisibleChanged: {
    root.appendDebugEvent("sessionVisibleChanged", {
      sessionVisible: root.sessionVisible
    })
    if (sessionVisible) {
      if (root.mode === "window" && !root.screenFrozen)
        root.refreshLiveWindowTargets()
      Qt.callLater(root.syncSelectorPreview)
    }
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    blockLoading: true
    atomicWrites: true
  }
  CaptureProvider {
    id: captureProvider
  }
  onModeChanged: root.appendDebugEvent("modeChanged", {
    mode: root.mode
  })
  onScreenFrozenChanged: {
    root.appendDebugEvent("screenFrozenChanged", {
      screenFrozen: root.screenFrozen
    })
    if (!root.screenFrozen) {
      root.frozenWindowToplevelRefreshPending = false
      if (root.mode === "window")
        root.refreshLiveWindowTargets()
      root.resetSelectionState()
      Qt.callLater(root.syncSelectorPreview)
    }
  }
  onInitialGrabRequestIdChanged: root.appendDebugEvent("initialGrabRequestIdChanged", {
    requestId: root.initialGrabRequestId
  })
  onScreenshotRequestIdChanged: root.appendDebugEvent("screenshotRequestIdChanged", {
    requestId: root.screenshotRequestId
  })
  onFrozenWindowCacheRequestIdChanged: root.appendDebugEvent("frozenWindowCacheRequestIdChanged", {
    requestId: root.frozenWindowCacheRequestId
  })
  onInitialFrozenGrabPendingChanged: root.appendDebugEvent("initialFrozenGrabPendingChanged", {
    initialFrozenGrabPending: root.initialFrozenGrabPending
  })
  Connections {
    target: captureProvider
    function onRequestFinished(requestId, filePath) {
      if (requestId === root.initialGrabRequestId) {
        if (!root.active)
          return
        root.abortPendingInternalCapture("hyprquickshot-initial-grab-finished")
        root.initialGrabRequestId = ""
        root.sessionVisible = true
        root.resetSelectionState()
        root.frozenFrame = ""
        root.frozenFrame = "file://" + filePath
        root.frozenFrameAttempts = 0
        root.initialFrozenGrabPending = false
        root.surfaceTransparencyActive = false
        Qt.callLater(root.syncSelectorPreview)
        return
      }

      if (requestId === root.screenshotRequestId) {
        if (!root.active)
          return
        root.screenshotRequestId = ""
        if (root.lastScreenshotPath)
          Common.ProcessHelper.execDetached(`wl-copy < "${root.lastScreenshotPath}" >/dev/null 2>&1`)
        root.notifyScreenshotSuccess()
        root.resetSelectionState()
        root.screenshotFailureKeepsSession = false
        root.deactivate()
      }

      if (String(requestId).startsWith("debug-window-capture")) {
        root.updateDebugCapture(requestId, {
          completedAt: Date.now(),
          filePath: filePath,
          status: "finished"
        })
        return
      }
    }
    function onRequestFailed(requestId, error) {
      if (requestId === root.initialGrabRequestId) {
        if (!root.active)
          return
        root.abortPendingInternalCapture("hyprquickshot-initial-grab-failed")
        root.initialGrabRequestId = ""
        Quickshell.execDetached(["notify-send", "-a", "HyprShot", "Failed to capture screen", error])
        root.deactivate()
        return
      }

      if (requestId === root.frozenWindowCacheRequestId) {
        if (!root.active || !root.screenFrozen)
          return
        console.log("[window-targets] frozen cache failed", "requestId=", requestId, "reason=", error)
        root.frozenWindowCacheRequestId = ""
        root.cleanupFrozenWindowCache()
        Quickshell.execDetached(["notify-send", "-a", "HyprShot", "Frozen window capture failed", error])
        root.deactivate()
        return
      }

      if (requestId === root.screenshotRequestId) {
        if (!root.active)
          return
        root.screenshotRequestId = ""
        Quickshell.execDetached(["notify-send", "-a", "HyprShot", "Screenshot failed", error])
        if (root.screenshotFailureKeepsSession) {
          root.screenshotFailureKeepsSession = false
          root.sessionVisible = true
          Qt.callLater(root.syncSelectorPreview)
        } else {
          root.deactivate()
        }
      }

      if (String(requestId).startsWith("debug-window-capture")) {
        root.updateDebugCapture(requestId, {
          completedAt: Date.now(),
          error: String(error || ""),
          status: "failed"
        })
      }
    }
    function onBatchFinished(requestId) {
      if (requestId !== root.frozenWindowCacheRequestId)
        return
      const readyTargets = []
      for (const target of root.frozenWindowTargets) {
        readyTargets.push({
          stableId: target.stableId,
          x: target.x,
          y: target.y,
          width: target.width,
          height: target.height,
          title: target.title,
          className: target.className,
          captureState: "ready",
          imagePath: target.imagePath
        })
      }
      root.frozenWindowCacheRequestId = ""
      root.frozenWindowTargets = readyTargets
      root.frozenWindowCacheState = "ready"
      Qt.callLater(root.syncSelectorPreview)
    }
    function onBatchFailed(requestId, error, completedCount) {
      if (requestId !== root.frozenWindowCacheRequestId)
        return
      if (!root.active || !root.screenFrozen)
        return
      console.log("[window-targets] frozen cache failed", "requestId=", requestId, "completedCount=", completedCount, "reason=", error)
      root.frozenWindowCacheRequestId = ""
      root.cleanupFrozenWindowCache()
      Quickshell.execDetached(["notify-send", "-a", "HyprShot", "Frozen window capture failed", error])
      root.deactivate()
    }
  }
  IpcHandler {
    target: "hyprquickshot-recording"
    function status(): string {
      return JSON.stringify({
        active: recordProcess.running,
        audioDevice: root.currentRecordingAudioDevice,
        audioMode: root.recordAudioMode,
        filePath: root.currentRecordingPath,
        pid: recordProcess.processId === null || recordProcess.processId === undefined ? 0 : Number(recordProcess.processId),
        state: root.recordingState
      })
    }
    function stop(): void {
      root.stopActiveRecording()
    }
  }
  IpcHandler {
    target: "hyprquickshot-debug"
    function state(): string {
      return root.debugStateJson()
    }
    function refreshWindows(): string {
      return root.debugRefreshWindows()
    }
    function setMode(modeValue: string): bool {
      return root.debugSetMode(modeValue)
    }
    function captureWindow(stableId: string): string {
      return root.debugCaptureWindow(stableId)
    }
    function captureStatus(): string {
      return root.debugCaptureStatusJson()
    }
    function debugHistory(): string {
      return JSON.stringify(root.debugEventHistory)
    }
  }
  Connections {
    target: root
    function onDebugEvent(eventName, payload) {
      root.appendDebugEvent(`freeze:${eventName}`, payload)
    }
  }
  Timer {
    id: frozenWindowToplevelRetry
    interval: 120
    repeat: false
    running: false
    onTriggered: {
      if (!root.frozenWindowToplevelRefreshPending)
        return
      if (!root.active || !root.screenFrozen || root.frozenFrame === "" || root.initialFrozenGrabPending) {
        root.appendDebugEvent("frozenWindowToplevelRetry:cancelled", {
          active: root.active,
          screenFrozen: root.screenFrozen,
          frozenFrame: String(root.frozenFrame || ""),
          initialFrozenGrabPending: root.initialFrozenGrabPending
        })
        root.frozenWindowToplevelRefreshPending = false
        return
      }
      root.appendDebugEvent("frozenWindowToplevelRetry", {
        allHyprlandToplevelCount: root.asList(root.allHyprlandToplevels).length
      })
      root.startFrozenWindowCacheCapture()
    }
  }
  Timer {
    id: grabDelay
    interval: root.grabDelayMs
    repeat: false
    running: false
    onTriggered: {
      if (!root.active)
        return
      root.grabReady = true
      root.selectFocusedMonitorAndGrab()
      Qt.callLater(root.resetSelectionState)
    }
  }
  Connections {
    target: Hyprland
    enabled: root.active && root.grabReady && root.activeScreen === null
    function onFocusedMonitorChanged() {
      root.selectFocusedMonitorAndGrab()
    }
  }
  Shortcut {
    enabled: root.active
    sequence: "Escape"
    onActivated: () => {
      if (root.recordingState === "recording") {
        root.stopActiveRecording()
        return
      }
      if (root.mode === "region" && root.regionSelectorItem && root.regionSelectorItem.selecting) {
        if (typeof root.regionSelectorItem.cancelSelection === "function")
          root.regionSelectorItem.cancelSelection()
        else
          root.resetSelectionState()
        return
      }
      root.deactivate()
    }
  }
  Shortcut {
    enabled: root.active
    sequence: "Q"
    onActivated: () => {
      if (root.recordingState === "recording")
        root.stopActiveRecording()
      else
        root.deactivate()
    }
  }
  Shortcut {
    enabled: root.active && root.recordingState !== "countdown" && root.recordingState !== "recording"
    sequence: "S"
    onActivated: root.toggleSaveMode()
  }
  Shortcut {
    enabled: root.active && root.recordingState !== "recording"
    sequence: "Tab"
    onActivated: root.toggleMode()
  }
  Timer {
    id: countdownTimer
    interval: root.countdownTickMs
    repeat: true
    running: false
    onTriggered: {
      if (root.countdownValue > 1) {
        root.countdownValue -= 1
        countdownOverlay.pulse()
      } else {
        countdownTimer.stop()
        root.startRecording(root.recordingSelection)
      }
    }
  }
  Process {
    id: recordDirectoryProcess
    property string stderrText: ""
    running: false
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: recordDirectoryProcess.stderrText = this.text
    }
    onRunningChanged: {
      if (running)
        recordDirectoryProcess.stderrText = ""
    }
    function onExited(code) {
      const plan = root.pendingRecordingPlan
      root.pendingRecordingPlan = null
      if (!plan)
        return
      if (code !== 0) {
        const detail = recordDirectoryProcess.stderrText || `mkdir failed (code ${code})`
        root.notifyRecordingFailure(detail)
        root.stopRecordFlow()
        root.deactivate()
        return
      }
      root.launchRecordingPlan(plan)
    }
  }
  Process {
    id: recordProcess
    property string stderrText: ""
    property string stdoutText: ""
    running: false
    stderr: StdioCollector {
      id: recordStderr
      waitForEnd: true
      onStreamFinished: recordProcess.stderrText = this.text
    }
    stdout: SplitParser {
      onRead: data => {
        const text = String(data || "").trim()
        if (text === "")
          return
        recordProcess.stdoutText = text
      }
    }
    function onExited(code) {
      const reason = recordProcess.stderrText || recordProcess.stdoutText || `Command failed (code ${code})`
      const hadRecording = root.recordingState === "recording"
      root.recordingState = "idle"
      root.sessionVisible = false
      root.awaitingScreenConfirm = false
      root.recordingSelection = null
      root.syncRecordFlag()
      if (code === 0 || (code === 130 && hadRecording))
        root.notifyRecordingSuccess()
      else if (reason.trim() !== "")
        root.notifyRecordingFailure(reason)
      root.clearRecordingMetadata()
      root.deactivate()
    }
    onRunningChanged: {
      if (running) {
        recordProcess.stdoutText = ""
        recordProcess.stderrText = ""
        root.syncRecordFlag()
      }
      root.syncGlobalState()
    }
  }
  Loader {
    id: regionSelectorLoader
    active: root.sessionVisible && !root.initialFrozenGrabPending
    anchors.fill: parent
    sourceComponent: Src.RegionSelector {
      anchors.fill: parent
      borderRadius: 10.0
      dimOpacity: 0.6
      outlineThickness: 2.0
      visible: (root.mode === "region" && root.recordingState !== "recording") || root.awaitingScreenConfirm
      onClicked: (x, y) => {
        if (!root.awaitingScreenConfirm)
          return
        const insideControls = x >= controlWrapper.x && x <= (controlWrapper.x + controlWrapper.width) && y >= controlWrapper.y && y <= (controlWrapper.y + controlWrapper.height)
        if (insideControls)
          return
        root.awaitingScreenConfirm = false
        if (!root.targetScreen)
          return
        if (root.recordingState === "selecting")
          root.beginCountdownForSelection({
            x: 0,
            y: 0,
            width: root.targetScreen.width,
            height: root.targetScreen.height
          })
        else
          root.processScreenshot(0, 0, root.targetScreen.width, root.targetScreen.height)
      }
      onRegionSelected: (x, y, width, height) => {
        if (root.awaitingScreenConfirm) {
          const insideControls = x >= controlWrapper.x && x <= (controlWrapper.x + controlWrapper.width) && y >= controlWrapper.y && y <= (controlWrapper.y + controlWrapper.height)
          if (insideControls)
            return
          root.awaitingScreenConfirm = false
          if (!root.targetScreen)
            return
          if (root.recordingState === "selecting") {
            root.beginCountdownForSelection({
              x: 0,
              y: 0,
              width: root.targetScreen.width,
              height: root.targetScreen.height
            })
          } else {
            root.processScreenshot(0, 0, root.targetScreen.width, root.targetScreen.height)
          }
          return
        }
        if (root.recordingState === "selecting") {
          root.beginCountdownForSelection({
            x,
            y,
            width,
            height
          })
          return
        }
        root.processScreenshot(x, y, width, height)
      }
    }
  }
  Loader {
    id: windowSelectorLoader
    active: root.sessionVisible && !root.initialFrozenGrabPending
    anchors.fill: parent
    sourceComponent: Src.WindowSelector {
      anchors.fill: parent
      borderRadius: 10.0
      dimOpacity: 0.6
      outlineThickness: 2.0
      visible: root.mode === "window" && root.recordingState !== "recording"
      windowTargets: root.currentWindowTargets
      onWindowSelected: target => {
        if (root.recordingState === "selecting") {
          root.beginCountdownForSelection({
            x: Number(target.x),
            y: Number(target.y),
            width: Number(target.width),
            height: Number(target.height)
          })
          return
        }
        root.processWindowScreenshot(target)
      }
    }
  }
  Ui.ControlBar {
    id: controlWrapper
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 32
    anchors.horizontalCenter: parent.horizontalCenter
    margin: 8
    colors: root.colors
    mode: root.mode
    recordingState: root.recordingState
    recordMode: root.recordMode
    saveToDisk: root.saveToDisk
    screenFrozen: root.screenFrozen
    audioMode: root.recordAudioMode
    windowModeAvailable: root.windowModeAvailable
    windowModeLoading: root.windowModeLoading
    onAudioModeSelected: selectedMode => root.setRecordAudioMode(selectedMode)
    onModeSelected: selectedMode => root.setMode(selectedMode)
    onRecordRequested: {
      root.toggleRecordFlow()
    }
    onSaveToDiskToggled: enabled => root.setSaveToDisk(enabled)
    onScreenFrozenToggled: frozen => {
      if (frozen === root.screenFrozen)
        return
      if (frozen)
        root.freezeNow()
      else
        root.unfreezeNow()
    }
  }
  Ui.CountdownOverlay {
    id: countdownOverlay
    active: root.recordingState === "countdown"
    center: root.countdownCenter
    colors: root.colors
    value: root.countdownValue
  }
  Item {
    id: fullMaskItem
    anchors.fill: parent
    visible: false
  }
  Region {
    id: fullMask
    item: fullMaskItem
  }
  Item {
    id: emptyMaskItem
    width: 0
    height: 0
    visible: false
  }
  Region {
    id: emptyMask
    item: emptyMaskItem
  }
}
