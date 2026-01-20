/**
 * @module WorkspacesModule
 * @description Hyprland workspace switcher (numbered workspaces)
 *
 * Features:
 * - Displays numbered workspaces (1-10)
 * - Shows active workspace highlight
 * - Click to switch workspace
 * - Per-monitor workspace filtering
 *
 * Dependencies:
 * - Quickshell.Hyprland: Workspace list and monitor info
 */
pragma ComponentBehavior: Bound
import ".."
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
            model: root.hyprland.workspaces

            delegate: WorkspaceButton {
                id: workspaceButton
                required property var modelData

                active: workspaceButton.modelData.active
                dispatchName: (workspaceButton.modelData.name && workspaceButton.modelData.name !== "") ? workspaceButton.modelData.name : workspaceButton.modelData.id
                fontFamily: Config.fontFamily
                fontSize: Config.fontSize
                hyprland: root.hyprland
                label: (workspaceButton.modelData.name && workspaceButton.modelData.name !== "") ? workspaceButton.modelData.name : workspaceButton.modelData.id
                urgent: workspaceButton.modelData.urgent
                visible: workspaceButton.modelData.id >= 0 && (!root.monitor || !workspaceButton.modelData.monitor || workspaceButton.modelData.monitor.name === root.monitor.name)
                workspace: workspaceButton.modelData
            }
        }
    }
}
