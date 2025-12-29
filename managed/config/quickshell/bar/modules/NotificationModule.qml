import ".."
import "../components"
import "../components/JsonUtils.js" as JsonUtils
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ModuleContainer {
    id: root

    property color iconColor: Config.accent
    property var iconMap: ({
            "notification": "󱅫",
            "none": "",
            "dnd-notification": "󰂠",
            "dnd-none": "󰪓",
            "inhibited-notification": "󰂛",
            "inhibited-none": "󰪑",
            "dnd-inhibited-notification": "󰂛",
            "dnd-inhibited-none": "󰪑"
        })
    property string iconText: "󱅫"
    property string onClickCommand: "swaync-client -t -sw"
    property string onRightClickCommand: "swaync-client -d -sw"
    property string statusAlt: "notification"
    property string statusTooltip: "Notifications"

    function isDndActive() {
        return root.statusAlt.indexOf("dnd") >= 0 || root.statusAlt.indexOf("inhibited") >= 0;
    }
    function updateFromPayload(payload) {
        if (!payload)
            return;

        const alt = payload.alt || payload.class || "";
        if (alt)
            root.statusAlt = alt;

        const icon = root.iconMap[root.statusAlt] || root.iconMap.notification;
        root.iconText = icon;
        if (payload.tooltip && payload.tooltip !== "")
            root.statusTooltip = payload.tooltip;
        else
            root.statusTooltip = "Notifications";
    }

    tooltipText: root.statusTooltip
    tooltipTitle: "Notifications"

    content: [
        IconLabel {
            color: root.iconColor
            font.pixelSize: Config.iconSize + Config.spaceHalfXs
            text: root.iconText
        }
    ]
    tooltipContent: Component {
        ColumnLayout {
            spacing: Config.space.sm

            TooltipCard {
                content: [
                    Text {
                        Layout.maximumWidth: 320
                        Layout.preferredWidth: 260
                        color: Config.textColor
                        font.family: Config.fontFamily
                        font.pixelSize: Config.fontSize
                        text: root.statusTooltip
                        wrapMode: Text.Wrap
                    }
                ]
            }
            TooltipActionsRow {
                ActionChip {
                    text: "Open"

                    onClicked: Quickshell.execDetached(["sh", "-c", root.onClickCommand])
                }
                ActionChip {
                    active: root.isDndActive()
                    text: root.isDndActive() ? "DND On" : "DND Off"

                    onClicked: Quickshell.execDetached(["sh", "-c", root.onRightClickCommand])
                }
            }
        }
    }

    Process {
        id: watchProcess

        command: ["swaync-client", "-swb"]
        running: true

        stdout: SplitParser {
            onRead: function (data) {
                const line = data.trim();
                if (!line)
                    return;

                const payload = JsonUtils.parseObject(line);
                if (payload)
                    root.updateFromPayload(payload);
            }
        }
    }
    MouseArea {
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        anchors.fill: parent

        onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton)
                Quickshell.execDetached(["sh", "-c", root.onRightClickCommand]);
            else
                Quickshell.execDetached(["sh", "-c", root.onClickCommand]);
        }
    }
}
