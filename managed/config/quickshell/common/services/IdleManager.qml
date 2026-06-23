import QtQml
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qsnative
import ".." as Common

Scope {
  id: root

  property bool initialized: false
  property bool dpmsOff: false
  property double nextSuspendAtMs: 0
  readonly property string settingsPath: Quickshell.shellPath("data/idle_settings.json")
  readonly property bool ignoreLidEvents: Common.GlobalState.idleIgnoreLidEvents

  IdleProvider {
    id: idleProvider
  }

  Component.onCompleted: {
    if (!idleProvider.loadSettings(root.settingsPath) && idleProvider.error.length > 0)
      console.warn("[IdleManager] " + idleProvider.error)

    Common.GlobalState.idleMonitorSleepTimeoutSec = idleProvider.displayOffTimeoutSec
    Common.GlobalState.idleSuspendTimeoutSec = idleProvider.suspendTimeoutSec
    Common.GlobalState.idleSuspendEnabled = idleProvider.suspendEnabled
    Common.GlobalState.idleIgnoreLidEvents = idleProvider.ignoreLidEvents
    if (!idleProvider.syncLidInhibitProcess(root.ignoreLidEvents) && idleProvider.error.length > 0)
      console.warn("[IdleManager] " + idleProvider.error)

    root.initialized = true
  }

  function displayOffTimeoutSec() {
    return idleProvider.clampTimeout(Math.round(Common.GlobalState.idleMonitorSleepTimeoutSec || 0))
  }

  function suspendTimeoutSec() {
    return idleProvider.clampTimeout(Math.round(Common.GlobalState.idleSuspendTimeoutSec || 0))
  }

  function saveSettings() {
    if (!idleProvider.saveSettings(
          root.settingsPath,
          root.displayOffTimeoutSec(),
          root.suspendTimeoutSec(),
          Common.GlobalState.idleSuspendEnabled,
          Common.GlobalState.idleIgnoreLidEvents
        )
        && idleProvider.error.length > 0) {
      console.warn("[IdleManager] " + idleProvider.error)
    }
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
      return idleProvider.statusJson(
        root.dpmsOff,
        root.nextSuspendAtMs,
        Common.GlobalState.idleSleepInhibited,
        Date.now()
      )
    }

    function setDisplayOffTimeout(seconds: int): void {
      Common.GlobalState.idleMonitorSleepTimeoutSec = idleProvider.clampTimeout(seconds)
    }

    function wake(): void {
      root.setDpms(true, "ipc wake")
    }
  }

  onIgnoreLidEventsChanged: {
    if (!root.initialized)
      return

    if (!idleProvider.syncLidInhibitProcess(root.ignoreLidEvents) && idleProvider.error.length > 0)
      console.warn("[IdleManager] " + idleProvider.error)
  }
}
