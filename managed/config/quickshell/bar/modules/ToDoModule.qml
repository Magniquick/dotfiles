import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell

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

    MouseArea {
        // ModuleContainer uses HoverHandler for tooltip,
        // but if we want it to stay open or toggle on click,
        // we might need more logic.
        // Based on other modules, they mostly use HoverHandler.

        anchors.fill: parent

        onClicked: {}
    }
}
