import QtQml
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import ".." as Common
import "../JsonUtils.js" as JsonUtils

Scope {
  id: root

  property bool initialized: false
  property bool dpmsOff: false
  property double nextSuspendAtMs: 0
  readonly property string settingsPath: Quickshell.shellPath("data/idle_settings.json")
  readonly property bool ignoreLidEvents: Common.GlobalState.idleIgnoreLidEvents

  FileView {
    id: settingsFile

    path: root.settingsPath
    blockLoading: true
    atomicWrites: true
  }

  Component.onCompleted: {
    const raw = settingsFile.text()
    if (raw && raw.length > 0) {
      const data = JsonUtils.parseObject(raw)
      if (!data) {
        console.warn("[IdleManager] failed to parse settings")
      } else {
        if (Number.isFinite(data.displayOffTimeoutSec))
          Common.GlobalState.idleMonitorSleepTimeoutSec = data.displayOffTimeoutSec
        if (Number.isFinite(data.suspendTimeoutSec))
          Common.GlobalState.idleSuspendTimeoutSec = data.suspendTimeoutSec
        if (typeof data.suspendEnabled === "boolean")
          Common.GlobalState.idleSuspendEnabled = data.suspendEnabled
        if (typeof data.ignoreLidEvents === "boolean")
          Common.GlobalState.idleIgnoreLidEvents = data.ignoreLidEvents
      }
    }

    root.initialized = true
  }

  function displayOffTimeoutSec() {
    return Math.max(0, Math.round(Common.GlobalState.idleMonitorSleepTimeoutSec || 0))
  }

  function suspendTimeoutSec() {
    return Math.max(0, Math.round(Common.GlobalState.idleSuspendTimeoutSec || 0))
  }

  function saveSettings() {
    const data = {
      displayOffTimeoutSec: root.displayOffTimeoutSec(),
      suspendTimeoutSec: root.suspendTimeoutSec(),
      suspendEnabled: Common.GlobalState.idleSuspendEnabled,
      ignoreLidEvents: Common.GlobalState.idleIgnoreLidEvents
    }
    settingsFile.setText(JSON.stringify(data))
  }

  function persistIdleSettings() {
    root.saveSettings()
    if (!Common.GlobalState.idleSuspendEnabled)
      root.nextSuspendAtMs = 0
  }

  function scheduleSuspend() {
    const timeout = root.suspendTimeoutSec()
    root.nextSuspendAtMs = timeout > 0 && Common.GlobalState.idleSuspendEnabled && root.dpmsOff ? Date.now() + timeout * 1000 : 0
  }

  function secondsLeft(targetMs) {
    if (!(targetMs > 0))
      return 0
    return Math.max(0, Math.ceil((targetMs - Date.now()) / 1000))
  }

  function setDpms(on, reason) {
    if (root.dpmsOff === !on)
      return
    root.dpmsOff = !on
    Hyprland.dispatch(`hl.dsp.dpms({ action = "${on ? "enable" : "disable"}" })`)
    console.info("[IdleManager] dpms " + (on ? "on" : "off") + " (" + reason + ")")
    if (on) {
      root.nextSuspendAtMs = 0
    } else {
      root.scheduleSuspend()
    }
  }

  function triggerSuspend() {
    if (!Common.GlobalState.idleSuspendEnabled)
      return
    Quickshell.execDetached(["systemctl", "suspend"])
  }

  Connections {
    target: Common.GlobalState

    function onIdleMonitorSleepTimeoutSecChanged() {
      if (!root.initialized)
        return
      root.persistIdleSettings()
    }

    function onIdleSuspendTimeoutSecChanged() {
      if (!root.initialized)
        return
      root.persistIdleSettings()
    }

    function onIdleSuspendEnabledChanged() {
      if (!root.initialized)
        return
      root.persistIdleSettings()
    }

    function onIdleIgnoreLidEventsChanged() {
      if (!root.initialized)
        return
      root.saveSettings()
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: Common.GlobalState.idleSleepInhibited && Common.GlobalState.idleSleepInhibitUntilMs > 0

    onTriggered: {
      if (Date.now() >= Common.GlobalState.idleSleepInhibitUntilMs)
        Common.GlobalState.clearSleepInhibit()
    }
  }

  Connections {
    target: Common.GlobalState

    function onIdleSleepInhibitedChanged() {
      if (Common.GlobalState.idleSleepInhibited) {
        root.setDpms(true, "sleep inhibited")
        return
      }
    }
  }

  IdleMonitor {
    enabled: root.displayOffTimeoutSec() > 0 && !Common.GlobalState.idleSleepInhibited
    respectInhibitors: true
    timeout: root.displayOffTimeoutSec()

    onIsIdleChanged: root.setDpms(!isIdle, isIdle ? "display idle timeout" : "activity")
  }

  IdleMonitor {
    enabled: Common.GlobalState.idleSuspendEnabled && root.suspendTimeoutSec() > 0 && root.dpmsOff && !Common.GlobalState.idleSleepInhibited
    respectInhibitors: true
    timeout: root.suspendTimeoutSec()

    onIsIdleChanged: {
      if (isIdle)
        root.triggerSuspend()
      else
        root.nextSuspendAtMs = 0
    }
  }

  IpcHandler {
    target: "idle"

    function status(): string {
      return JSON.stringify({
        managedBy: "quickshell",
        dpmsOff: root.dpmsOff,
        displayOffTimeoutSec: root.displayOffTimeoutSec(),
        displayOffSecondsLeft: root.dpmsOff ? 0 : null,
        suspendEnabled: Common.GlobalState.idleSuspendEnabled,
        suspendTimeoutSec: root.suspendTimeoutSec(),
        suspendSecondsLeft: root.secondsLeft(root.nextSuspendAtMs),
        sleepInhibited: Common.GlobalState.idleSleepInhibited,
        ignoreLidEvents: Common.GlobalState.idleIgnoreLidEvents
      })
    }

    function setDisplayOffTimeout(seconds: int): void {
      Common.GlobalState.idleMonitorSleepTimeoutSec = Math.max(0, seconds)
    }

    function wake(): void {
      root.setDpms(true, "ipc wake")
    }
  }

  Process {
    id: lidInhibitProcess

    command: ["systemd-inhibit", "--what=handle-lid-switch", "--who=Quickshell", "--why=Ignore lid close from Caffeine", "--mode=block", "sleep", "infinity"]
    running: root.ignoreLidEvents
  }
}
