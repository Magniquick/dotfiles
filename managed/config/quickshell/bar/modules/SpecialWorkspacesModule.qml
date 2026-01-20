/**
 * @module SpecialWorkspacesModule
 * @description Hyprland special workspace buttons (scratchpads)
 *
 * Features:
 * - Displays special workspaces (special:name)
 * - Custom icon mapping per workspace name
 * - Click to toggle special workspace
 *
 * Dependencies:
 * - Quickshell.Hyprland: Special workspace list
 */
pragma ComponentBehavior: Bound
import ".."
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

Item {
    id: root

    readonly property var hyprland: Hyprland
    property var iconMap: ({})
    property var monitor: root.screen ? hyprland.monitorFor(root.screen) : null
    property var screen

    function iconFor(workspace) {
        const name = specialName(workspace.name);
        return root.iconMap[name] || "";
    }
    function isSpecial(workspace) {
        if (!workspace)
            return false;

        if (workspace.name && workspace.name.startsWith("special:"))
            return true;

        return workspace.id < 0;
    }
    function specialName(name) {
        if (!name)
            return "";

        return name.startsWith("special:") ? name.slice(8) : name;
    }

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
                fontFamily: Config.iconFontFamily
                fontSize: Config.iconSize
                hyprland: root.hyprland
                label: root.iconFor(workspaceButton.modelData)
                uniformWidth: false
                urgent: workspaceButton.modelData.urgent
                visible: root.isSpecial(workspaceButton.modelData) && root.iconFor(workspaceButton.modelData) !== "" && (!root.monitor || !workspaceButton.modelData.monitor || workspaceButton.modelData.monitor.name === root.monitor.name)
                workspace: workspaceButton.modelData
            }
        }
    }
}
