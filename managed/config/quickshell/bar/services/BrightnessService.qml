pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qsnative

import "../components"
import "../../common" as Common

Item {
  id: root
  visible: false

  // Dependencies
  property bool ddcutilAvailable: false

  // Map: connector name (e.g. "DP-1") -> i2c bus number (string, e.g. "3")
  property var ddcByConnector: ({})
  property int ddcVersion: 0

  // Created per-screen monitor objects.
  property var _monitors: []

  // Bind to screens list so QML notifies on hotplug; we rebuild on change.
  property var screens: Quickshell.screens

  function getMonitorForScreen(screen) {
    if (!screen)
      return null;
    const name = screen.name;
    for (const m of root._monitors) {
      if (m && (m.screen === screen || (name && m.screenName === name)))
        return m;
    }
    return null;
  }

  function scheduleRebuild() {
    if (!rebuildTimer.running)
      rebuildTimer.start();
  }

  function rebuildMonitors() {
    // Destroy old objects.
    for (const m of root._monitors) {
      if (m && typeof m.destroy === "function")
        m.destroy();
    }
    root._monitors = [];

    // Create one monitor object per screen.
    const next = [];
    for (const s of root.screens || []) {
      const obj = monitorComp.createObject(root, { screen: s });
      if (obj)
        next.push(obj);
    }
    root._monitors = next;
  }

  function scheduleDdcDetect() {
    if (!root.ddcutilAvailable)
      return;
    if (!ddcDetectTimer.running)
      ddcDetectTimer.start();
  }

  Component.onCompleted: {
    backlightProvider.start();
    Common.DependencyCheck.require("ddcutil", "BrightnessService", function(available) {
      root.ddcutilAvailable = available;
      if (available)
        root.scheduleDdcDetect();
    });

    root.scheduleRebuild();
  }

  onScreensChanged: {
    root.scheduleRebuild();
    // New monitors may appear/disappear; re-detect DDC mapping.
    root.scheduleDdcDetect();
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
    onTriggered: {
      if (ddcDetectProc.running)
        ddcDetectProc.running = false;
      ddcDetectProc.running = true;
    }
  }

  Process {
    id: ddcDetectProc
    running: false
    command: ["ddcutil", "detect", "--brief", "--sleep-multiplier=0.5"]

    stdout: StdioCollector {
      onStreamFinished: {
        const text = (this.text || "").trim();
        if (text === "") {
          root.ddcByConnector = ({});
          root.ddcVersion++;
          return;
        }

        const blocks = text.split(/\n\s*\n/);
        const map = {};
        for (const b of blocks) {
          // Skip blocks that explicitly say DDC/CI is unsupported.
          if (/does not support DDC\/CI/i.test(b) || /Invalid display/i.test(b))
            continue;
          const connectorMatch = b.match(/DRM\s*connector:\s*(?:card\d+-)?(.+)/i);
          // Avoid matching literal '/' to keep the QML/JS regexp parser happy.
          const busMatch = b.match(/I2C\s*bus:\s*.*i2c-(\d+)/i);
          if (!connectorMatch || !busMatch)
            continue;
          const connector = (connectorMatch[1] || "").trim();
          const busNum = (busMatch[1] || "").trim();
          if (connector !== "" && busNum !== "")
            map[connector] = busNum;
        }

        root.ddcByConnector = map;
        root.ddcVersion++;
      }
    }
  }

  BacklightProvider {
    id: backlightProvider
  }
  // Expose via a real property so nested components can reliably access it.
  readonly property var backlight: backlightProvider

  Component {
    id: monitorComp

    BrightnessMonitor { }
  }

  component BrightnessMonitor: QtObject {
    id: monitor

    required property var screen
    readonly property string screenName: monitor.screen ? monitor.screen.name : ""

    readonly property bool isInternalOutput: /^eDP-|^LVDS-|^DSI-/i.test(monitor.screenName)

    // DDC mapping. This is intentionally connector-name based.
    readonly property string ddcBusNum: {
      root.ddcVersion; // reactive
      const bus = root.ddcByConnector[monitor.screenName];
      return bus ? String(bus) : "";
    }
    // Prefer the native backlight provider for internal panels (eDP/LVDS/DSI), even
    // if ddcutil detects an i2c bus for them.
    readonly property bool isDdc: root.ddcutilAvailable && monitor.ddcBusNum !== "" && !monitor.isInternalOutput

    // Internal backlight paths (if available).
    readonly property string backlightDevice: root.backlight.device || ""

    property real brightness: root.backlight.available ? (root.backlight.brightness_percent / 100.0) : 0
    property int maxBrightness: 100
    property string error: ""

    readonly property string method: {
      if (monitor.isInternalOutput && root.backlight.available)
        return "backlight";
      if (monitor.isDdc)
        return "ddc";
      return "none";
    }
    readonly property bool brightnessControlAvailable: {
      if (monitor.method === "ddc")
        return root.ddcutilAvailable && monitor.ddcBusNum !== "";
      if (monitor.method === "backlight")
        return root.backlight.available;
      return false;
    }

    // DDC state
    property bool _ddcGetRunning: false
    property bool _ddcSetRunning: false
    property real _pendingSet: NaN

    function clamp01(x) {
      const n = Number(x);
      if (!isFinite(n))
        return 0;
      return Math.max(0, Math.min(1, n));
    }

    function percentToNormalized(p) {
      const n = Number(p);
      if (!isFinite(n))
        return 0;
      // Prevent fully black by clamping to 1% on controllable displays.
      const clamped = Math.max(1, Math.min(100, Math.round(n)));
      return clamped / 100.0;
    }

    function setBrightness(value) {
      if (!monitor.brightnessControlAvailable)
        return;

      const next = monitor.clamp01(value);
      // Apply immediately for UI feedback.
      monitor.brightness = next;

      if (monitor.method === "ddc") {
        monitor._pendingSet = next;
        ddcSetTimer.restart();
        return;
      }

      if (monitor.method === "backlight") {
        const percent = Math.max(1, Math.min(100, Math.round(next * 100)));
        root.backlight.setBrightness(percent);
      }
    }

    function refresh() {
      if (monitor.method === "ddc") {
        if (!ddcGetProc.running)
          ddcGetProc.running = true;
        return;
      }
      if (monitor.method === "backlight") {
        root.backlight.refresh();
      }
    }

    function parseDdcVcp10(output) {
      // Typical: "VCP 10 C 50 100"
      // Sometimes values may be hex: "0x0032 0x0064".
      const s = (output || "").trim();
      const tokens = s.match(/0x[0-9a-fA-F]+|\\d+/g) || [];
      if (tokens.length < 2)
        return null;

      function parseNum(t) {
        if (t.startsWith("0x") || t.startsWith("0X"))
          return parseInt(t, 16);
        return parseInt(t, 10);
      }

      // Heuristic: last two numeric tokens are current and max.
      const cur = parseNum(tokens[tokens.length - 2]);
      const max = parseNum(tokens[tokens.length - 1]);
      if (!isFinite(cur) || !isFinite(max) || max <= 0)
        return null;
      return { current: cur, max: max };
    }

    Component.onCompleted: {
      if (monitor.method === "backlight")
        monitor.refresh();
    }

    onIsDdcChanged: {
      if (monitor.isDdc)
        monitor.refresh();
    }

    onDdcBusNumChanged: {
      if (monitor.isDdc)
        monitor.refresh();
    }

    readonly property Connections backlightConnections: Connections {
      target: root.backlight

      function onBrightness_percentChanged() {
        if (monitor.method === "backlight")
          monitor.brightness = root.backlight.brightness_percent / 100.0;
      }
      function onAvailableChanged() {
        if (monitor.method === "backlight")
          monitor.brightness = root.backlight.available ? (root.backlight.brightness_percent / 100.0) : 0;
      }
      function onErrorChanged() {
        if (monitor.method === "backlight")
          monitor.error = root.backlight.error || "";
      }
    }

    readonly property Timer ddcSetTimer: Timer {
      interval: 300
      repeat: false
      onTriggered: {
        if (monitor.method !== "ddc")
          return;
        if (monitor._ddcSetRunning)
          return;
        const next = monitor._pendingSet;
        if (!isFinite(next))
          return;
        monitor._pendingSet = NaN;

        // Compute raw value based on last known max. If unknown, assume 100.
        const max = monitor.maxBrightness > 0 ? monitor.maxBrightness : 100;
        const raw = Math.max(1, Math.min(max, Math.round(next * max)));

        monitor._ddcSetRunning = true;
        ddcSetProc.command = ["ddcutil", "-b", monitor.ddcBusNum, "--sleep-multiplier=0.05", "setvcp", "10", String(raw)];
        ddcSetProc.running = true;
      }
    }

    readonly property Process ddcGetProc: Process {
      running: false
      command: ["ddcutil", "-b", monitor.ddcBusNum, "--sleep-multiplier=0.05", "getvcp", "10", "--brief"]
      stdout: StdioCollector {
        onStreamFinished: {
          monitor._ddcGetRunning = false;
          const parsed = monitor.parseDdcVcp10(this.text || "");
          if (!parsed) {
            monitor.error = "DDC read failed";
            return;
          }
          monitor.error = "";
          monitor.maxBrightness = parsed.max;
          monitor.brightness = Math.max(0, Math.min(1, parsed.current / parsed.max));
        }
      }
      onRunningChanged: {
        if (running)
          monitor._ddcGetRunning = true;
      }
      onExited: (exitCode, exitStatus) => {
        // Make running edge-triggered for repeated refreshes.
        if (ddcGetProc.running)
          ddcGetProc.running = false;
      }
    }

    readonly property Process ddcSetProc: Process {
      running: false
      onExited: (exitCode, exitStatus) => {
        monitor._ddcSetRunning = false;
        // Refresh after setting to sync with actual device state.
        monitor.refresh();
      }
    }
  }
}
