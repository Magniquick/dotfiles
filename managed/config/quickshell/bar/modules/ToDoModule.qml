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
 * - tools/todoist-sync.sh: Go Sync API helper launcher
 * - ~/.local/bin/custom/todoist.sh: Todoist launcher script
 */
pragma ComponentBehavior: Bound
import ".."
import "../components"
import QtQuick
import "../../common" as Common

ModuleContainer {
    id: root

    property bool dropdownPinned: false
    readonly property int taskCount: {
        const data = TodoistService.data;
        if (!data || !Array.isArray(data.today))
            return 0;
        return data.today.length;
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

    onClicked: Common.ProcessHelper.execDetached(root.tooltipBrowserLink)
    onRightClicked: TodoistService.refresh("manual")

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
