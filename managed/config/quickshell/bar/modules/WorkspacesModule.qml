import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

Item {
    id: root

    property var screen
    readonly property var hyprland: Hyprland
    property var monitor: root.screen ? hyprland.monitorFor(root.screen) : null

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
                label: (modelData.name && modelData.name !== "") ? modelData.name : modelData.id
                dispatchName: (modelData.name && modelData.name !== "") ? modelData.name : modelData.id
                active: modelData.active
                urgent: modelData.urgent
                visible: modelData.id >= 0 && (!root.monitor || !modelData.monitor || modelData.monitor.name === root.monitor.name)
                fontFamily: Config.fontFamily
                fontSize: Config.fontSize
            }
        }
    }
}
