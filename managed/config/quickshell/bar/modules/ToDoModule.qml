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
 * - bar/scripts/src/todoist-api: Rust binary for Todoist API
 * - ~/.local/bin/custom/todoist.sh: Todoist launcher script
 */
pragma ComponentBehavior: Bound
import ".."
import "../components"
import QtQuick

ModuleContainer {
    id: root

    property bool dropdownPinned: false

    tooltipBrowserLink: "runapp ~/.local/bin/custom/todoist.sh"
    tooltipHoverable: true
    tooltipPinned: dropdownPinned
    tooltipRefreshing: false
    tooltipShowBrowserIcon: true
    tooltipShowRefreshIcon: true
    tooltipSubtitle: ""
    tooltipTitle: "Tasks"

    content: [
        Text {
            color: Config.m3.tertiary
            font.family: Config.iconFontFamily
            font.pixelSize: Config.iconSize
            text: "󰄭"
            verticalAlignment: Text.AlignVCenter
        }
    ]
    tooltipContent: Component {
        ToDoModule {
            width: 320

            Component.onCompleted: {
                root.tooltipRefreshing = Qt.binding(() => {
                    return loading;
                });
                root.dropdownPinned = Qt.binding(() => {
                    return dropdownActive;
                });
                root.tooltipSubtitle = Qt.binding(() => {
                    if (!lastUpdated || lastUpdated === "")
                        return "";

                    return usingCache ? ("Cached " + lastUpdated) : lastUpdated;
                });
                root.tooltipRefreshRequested.connect(refresh);
            }
        }
    }

}
