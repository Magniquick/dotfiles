import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell

ModuleContainer {
    id: root

    property bool dropdownPinned: false

    tooltipTitle: "Tasks"
    tooltipHoverable: true
    tooltipShowRefreshIcon: true
    tooltipShowBrowserIcon: true
    tooltipBrowserLink: "runapp ~/.local/bin/custom/todoist.sh"
    tooltipRefreshing: false
    tooltipPinned: dropdownPinned
    tooltipSubtitle: ""
    content: [
        Text {
            text: "󰄭"
            color: Config.lavender
            font.family: Config.iconFontFamily
            font.pixelSize: Config.iconSize
            verticalAlignment: Text.AlignVCenter
        }
    ]

    MouseArea {
        // ModuleContainer uses HoverHandler for tooltip,
        // but if we want it to stay open or toggle on click,
        // we might need more logic.
        // Based on other modules, they mostly use HoverHandler.

        anchors.fill: parent
        onClicked: {}
    }

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
