import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

Item {
    id: root

    readonly property var hyprland: Hyprland
    property var monitor: root.screen ? hyprland.monitorFor(root.screen) : null
    property var screen

    implicitHeight: workspaceRow.implicitHeight
    implicitWidth: workspaceRow.implicitWidth

    RowLayout {
        id: workspaceRow

        spacing: Config.groupModuleSpacing

        Repeater {
            model: hyprland.workspaces

            delegate: WorkspaceButton {
                active: modelData.active
                dispatchName: (modelData.name && modelData.name !== "") ? modelData.name : modelData.id
                fontFamily: Config.fontFamily
                fontSize: Config.fontSize
                hyprland: hyprland
                label: (modelData.name && modelData.name !== "") ? modelData.name : modelData.id
                urgent: modelData.urgent
                visible: modelData.id >= 0 && (!root.monitor || !modelData.monitor || modelData.monitor.name === root.monitor.name)
                workspace: modelData
            }
        }
    }
}
