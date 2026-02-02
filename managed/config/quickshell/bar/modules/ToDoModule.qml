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
    property var todoData: null
    readonly property int taskCount: root.todoData ? root.todoData.tasks.length : 0
    // Intentionally no hover label; keep pill compact.

    tooltipBrowserLink: "runapp todoist.sh"
    tooltipHoverable: true
    tooltipPinned: dropdownPinned
    tooltipRefreshing: false
    tooltipShowBrowserIcon: true
    tooltipShowRefreshIcon: true
    tooltipSubtitle: ""
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
                text: root.todoData ? String(root.taskCount) : ""
            }
        }
    ]
    tooltipContent: Component {
        ToDoModule {
            width: 320

            Component.onCompleted: {
                root.todoData = this;
                root.tooltipRefreshing = Qt.binding(() => {
                    return loading;
                });
                root.dropdownPinned = Qt.binding(() => {
                    return dropdownActive;
                });
                root.tooltipSubtitle = Qt.binding(() => {
                    if (!lastUpdated || lastUpdated === "")
                        return "";

                    return "Synced " + lastUpdated;
                });
                root.tooltipRefreshRequested.connect(refresh);
            }
        }
    }
}
