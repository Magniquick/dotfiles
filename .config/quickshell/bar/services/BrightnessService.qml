pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qsnative

Item {
  id: root
  visible: false

  // Created per-screen monitor objects.
  property var _monitors: []

  // Bind to screens list so QML notifies on hotplug; we rebuild on change.
  property var screens: Quickshell.screens

  function getMonitorForScreen(screen) {
    if (!screen)
      return null
    const name = screen.name
    for (const m of root._monitors) {
      if (m && (m.screen === screen || (name && m.screenName === name)))
        return m
    }
    return null
  }

  function scheduleRebuild() {
    if (!rebuildTimer.running)
      rebuildTimer.start()
  }

  function rebuildMonitors() {
    // Destroy old objects.
    for (const m of root._monitors) {
      if (m && typeof m.destroy === "function")
        m.destroy()
    }
    root._monitors = [];

    // Create one monitor object per screen.
    const next = []
    for (const s of root.screens || []) {
      const obj = monitorComp.createObject(root, {
        screen: s
      })
      if (obj)
        next.push(obj)
    }
    root._monitors = next
  }

  function scheduleDdcDetect() {
    if (!ddcDetectTimer.running)
      ddcDetectTimer.start()
  }

  Component.onCompleted: {
    backlightProvider.start()
    root.scheduleRebuild()
  }

  onScreensChanged: {
    root.scheduleRebuild();
    // New monitors may appear/disappear; re-detect DDC mapping.
    root.scheduleDdcDetect()
  }

  Timer {
    id: rebuildTimer
    interval: 0
    repeat: false
    onTriggered: root.rebuildMonitors()
  }

  Timer {
    id: ddcDetectTimer
    interval: 200
    repeat: false
    onTriggered: root.backlight.refreshDdc()
  }

  BacklightProvider {
    id: backlightProvider
  }
  // Expose via a real property so nested components can reliably access it.
  readonly property var backlight: backlightProvider

  Component {
    id: monitorComp

    BrightnessMonitor {}
  }

  component BrightnessMonitor: QtObject {
    id: monitor

    required property var screen
    readonly property string screenName: monitor.screen ? monitor.screen.name : ""

    readonly property bool isInternalOutput: /^eDP-|^LVDS-|^DSI-/i.test(monitor.screenName)

    // DDC mapping. This is intentionally connector-name based.
    readonly property string ddcBusNum: {
      root.backlight.ddc_version
      const bus = root.backlight.ddcBusForConnector(monitor.screenName)
      return bus ? String(bus) : ""
    }
    // Prefer the native backlight provider for internal panels (eDP/LVDS/DSI), even
    // if ddcutil detects an i2c bus for them.
    readonly property bool isDdc: root.backlight.ddcutil_available && monitor.ddcBusNum !== "" && !monitor.isInternalOutput

    // Internal backlight paths (if available).
    readonly property string backlightDevice: root.backlight.device || ""

    property real brightness: root.backlight.available ? (root.backlight.brightness_percent / 100.0) : 0
    property int maxBrightness: 100
    property string error: ""

    readonly property string method: {
      if (monitor.isInternalOutput && root.backlight.available)
        return "backlight"
      if (monitor.isDdc)
        return "ddc"
      return "none"
    }
    readonly property bool brightnessControlAvailable: {
      if (monitor.method === "ddc")
        return root.backlight.ddcutil_available && monitor.ddcBusNum !== ""
      if (monitor.method === "backlight")
        return root.backlight.available
      return false
    }

    property real _pendingSet: NaN

    function clamp01(x) {
      const n = Number(x)
      if (!isFinite(n))
        return 0
      return Math.max(0, Math.min(1, n))
    }

    function setBrightness(value) {
      if (!monitor.brightnessControlAvailable)
        return
      const next = monitor.clamp01(value);
      // Apply immediately for UI feedback.
      monitor.brightness = next

      if (monitor.method === "ddc") {
        monitor._pendingSet = next
        ddcSetTimer.restart()
        return
      }

      if (monitor.method === "backlight") {
        const percent = Math.max(1, Math.min(100, Math.round(next * 100)))
        root.backlight.setBrightness(percent)
      }
    }

    function refresh() {
      if (monitor.method === "ddc") {
        root.backlight.refreshDdcBrightness(monitor.screenName)
        return
      }
      if (monitor.method === "backlight") {
        root.backlight.refresh()
      }
    }

    Component.onCompleted: {
      if (monitor.method === "backlight")
        monitor.refresh()
    }

    onIsDdcChanged: {
      if (monitor.isDdc)
        monitor.refresh()
    }

    onDdcBusNumChanged: {
      if (monitor.isDdc)
        monitor.refresh()
    }

    readonly property Connections backlightConnections: Connections {
      target: root.backlight

      function onBrightness_percentChanged() {
        if (monitor.method === "backlight")
          monitor.brightness = root.backlight.brightness_percent / 100.0
      }
      function onAvailableChanged() {
        if (monitor.method === "backlight")
          monitor.brightness = root.backlight.available ? (root.backlight.brightness_percent / 100.0) : 0
      }
      function onErrorChanged() {
        if (monitor.method === "backlight")
          monitor.error = root.backlight.error || ""
      }
      function onDdc_versionChanged() {
        if (monitor.method === "ddc") {
          monitor.maxBrightness = root.backlight.ddcMaxBrightness(monitor.screenName)
          monitor.error = root.backlight.ddcError(monitor.screenName)
          const percent = root.backlight.ddcBrightnessPercent(monitor.screenName)
          if (percent > 0)
            monitor.brightness = Math.max(0, Math.min(1, percent / 100.0))
        }
      }
    }

    readonly property Timer ddcSetTimer: Timer {
      interval: 300
      repeat: false
      onTriggered: {
        if (monitor.method !== "ddc")
          return
        const next = monitor._pendingSet
        if (!isFinite(next))
          return
        monitor._pendingSet = NaN;

        const percent = Math.max(1, Math.min(100, Math.round(next * 100)))
        root.backlight.setDdcBrightness(monitor.screenName, percent)
      }
    }
  }
}
