import ".."
import "../components"
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
            model: hyprland.workspaces

            delegate: WorkspaceButton {
                active: modelData.active
                dispatchName: (modelData.name && modelData.name !== "") ? modelData.name : modelData.id
                fontFamily: Config.iconFontFamily
                fontSize: Config.iconSize
                hyprland: hyprland
                label: root.iconFor(modelData)
                uniformWidth: false
                urgent: modelData.urgent
                visible: root.isSpecial(modelData) && root.iconFor(modelData) !== "" && (!root.monitor || !modelData.monitor || modelData.monitor.name === root.monitor.name)
                workspace: modelData
            }
        }
    }
}
