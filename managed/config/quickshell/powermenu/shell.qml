import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls

ShellRoot {
  id: root

  property bool powermenuVisible: false
  property string powermenuSelection: ""
  property string powermenuHover: ""

  readonly property var palette: ColorPalette.palette

  function resetState() {
    powermenuSelection = ""
    powermenuHover = ""
  }

  function togglePowermenu() {
    const next = !powermenuVisible
    if (next) resetState() // clear stale hover/selection before showing
    powermenuVisible = next
    if (!next) resetState()
  }

  function runAction(action) {
    var cmd = []
    if (action === "Poweroff") cmd = ["systemctl", "poweroff"]
    else if (action === "Reboot") cmd = ["systemctl", "reboot"]
    else if (action === "Suspend") cmd = ["systemctl", "suspend"]
    else if (action === "Hibernate") cmd = ["systemctl", "hibernate"]
    else if (action === "Exit") cmd = ["loginctl", "lock-session"]
    else if (action === "Windows") cmd = ["systemctl", "reboot", "--boot-loader-entry=auto-windows"]

    if (cmd.length === 0) return
    actionProcess.command = cmd
    actionProcess.running = true
  }

  function onButton(action) {
    if (powermenuSelection === action) {
      powermenuVisible = false
      runAction(action)
      resetState()
    } else {
      powermenuSelection = action
    }
  }

  Process {
    id: actionProcess
    running: false
  }

  IpcHandler {
    target: "powermenu"
    function toggle(): void { root.togglePowermenu() }
    function show(): void { root.powermenuVisible = true; root.resetState() }
    function hide(): void { root.powermenuVisible = false; root.resetState() }
  }

  Powermenu {
    id: powermenu
    visible: powermenuVisible
    targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    colors: palette
    selection: powermenuSelection
    hoverAction: powermenuHover
    onRequestClose: {
      powermenuVisible = false
      resetState()
    }
    onActionInvoked: (actionName) => onButton(actionName)
    onHoverUpdated: (actionName) => powermenuHover = actionName
  }
}
