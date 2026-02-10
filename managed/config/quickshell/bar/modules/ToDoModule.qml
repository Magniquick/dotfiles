/**
 * @module ToDoModule
 * @description Task management module with Todoist integration
 *
 * Features:
 * - Task icon in bar
 * - Tooltip shows task list from Todoist API
 * - Click opens Todoist app
 * - Refresh button to sync tasks
 *
 * Dependencies:
 * - common/modules/qs-native: CXX-Qt QML module for Todoist API
 * - ~/.local/bin/custom/todoist.sh: Todoist launcher script
 */
pragma ComponentBehavior: Bound
import ".."
import "../components"
import QtQuick

ModuleContainer {
    id: root

    property bool dropdownPinned: false
    readonly property int taskCount: {
        const data = TodoistService.data;
        if (!data)
            return 0;
        let count = 0;
        if (Array.isArray(data.today))
            count += data.today.length;
        const projects = data.projects;
        if (projects && typeof projects === "object") {
            const keys = Object.keys(projects);
            for (let i = 0; i < keys.length; i++) {
                const list = projects[keys[i]];
                if (Array.isArray(list))
                    count += list.length;
            }
        }
        return count;
    }
    // Intentionally no hover label; keep pill compact.

    tooltipBrowserLink: ["runapp", "todoist.sh"]
    tooltipHoverable: true
    tooltipPinned: dropdownPinned
    tooltipRefreshing: TodoistService.loading
    tooltipShowBrowserIcon: true
    tooltipShowRefreshIcon: true
    tooltipSubtitle: TodoistService.lastUpdatedLabel ? ("Synced " + TodoistService.lastUpdatedLabel) : ""
    tooltipTitle: "Tasks"

    content: [
        Row {
            spacing: root.contentSpacing

            IconLabel {
                color: Config.color.tertiary
                font.pixelSize: Config.iconSize
                text: "󰄭"
            }
            BarLabel {
                color: Config.color.tertiary
                font.pixelSize: Config.fontSize
                text: root.taskCount > 0 ? String(root.taskCount) : ""
            }
        }
    ]

    onTooltipRefreshRequested: TodoistService.refresh("manual")

    tooltipContent: Component {
        ToDoModule {
            id: todoTooltip
            width: 320

            Binding {
                target: root
                property: "dropdownPinned"
                value: todoTooltip.dropdownActive
            }
        }
    }
}
