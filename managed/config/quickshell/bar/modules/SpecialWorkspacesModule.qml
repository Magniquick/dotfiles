import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import ".."
import "../components"

Item {
  id: root
  property var screen
  property var iconMap: ({})

  readonly property var hyprland: Hyprland

  property var monitor: root.screen ? hyprland.monitorFor(root.screen) : null

  function specialName(name) {
    if (!name)
      return ""
    return name.startsWith("special:") ? name.slice(8) : name
  }

  function isSpecial(workspace) {
    if (!workspace)
      return false
    if (workspace.name && workspace.name.startsWith("special:"))
      return true
    return workspace.id < 0
  }

  function iconFor(workspace) {
    const name = specialName(workspace.name)
    return root.iconMap[name] || ""
  }

  implicitWidth: workspaceRow.implicitWidth
  implicitHeight: workspaceRow.implicitHeight

  RowLayout {
    id: workspaceRow
    spacing: Config.groupModuleSpacing

    Repeater {
      model: hyprland.workspaces

      delegate: WorkspaceButton {
        workspace: modelData
        hyprland: hyprland
        label: root.iconFor(modelData)
        dispatchName: (modelData.name && modelData.name !== "") ? modelData.name : modelData.id
        active: modelData.active
        urgent: modelData.urgent
        visible: root.isSpecial(modelData) &&
          root.iconFor(modelData) !== "" &&
          (!root.monitor || !modelData.monitor || modelData.monitor.name === root.monitor.name)
        fontFamily: Config.iconFontFamily
        fontSize: Config.iconSize
        uniformWidth: false
      }
    }
  }
}
