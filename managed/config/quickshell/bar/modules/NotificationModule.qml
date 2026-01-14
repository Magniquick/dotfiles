/**
 * @module NotificationModule
 * @description Notification status indicator with Do Not Disturb support via SwayNC
 *
 * Features:
 * - Real-time notification status monitoring via swaync-client
 * - Do Not Disturb (DND) status indicator
 * - Notification count display
 * - Interactive controls (toggle panel, toggle DND)
 * - Dynamic icons for different states (normal, DND, inhibited)
 * - Automatic crash recovery for watch process (exponential backoff)
 *
 * SwayNC Integration:
 * - swaync-client -swb: Subscribe to status updates (watch mode)
 * - swaync-client -t -sw: Toggle notification panel
 * - swaync-client -d -sw: Toggle Do Not Disturb mode
 *
 * Status States:
 * - "notification": Has unread notifications
 * - "none": No notifications
 * - "dnd-notification": DND enabled with notifications
 * - "dnd-none": DND enabled, no notifications
 * - "inhibited-notification": Notifications inhibited with unread
 * - "inhibited-none": Notifications inhibited, no unread
 *
 * Icon Mapping:
 * - Normal with notifications: 󱅫
 * - Normal without notifications: (empty)
 * - DND with notifications: 󰂠
 * - DND without notifications: 󰪓
 * - Inhibited with notifications: 󰂛
 * - Inhibited without notifications: 󰪑
 *
 * Dependencies:
 * - swaync (SwayNC): Notification daemon for Wayland
 * - swaync-client: Command-line client for SwayNC control
 *
 * Configuration:
 * - onClickCommand: Command for left click (default: toggle panel)
 * - onRightClickCommand: Command for right click (default: toggle DND)
 * - iconColor: Icon color (default: Config.m3.primary)
 *
 * Performance:
 * - Event-driven updates via watch mode (no polling)
 * - Lightweight JSON parsing with fallback handling
 * - Automatic crash recovery with exponential backoff
 *
 * Error Handling:
 * - Automatic restart of watch process on crash (1s, 2s, 4s, 8s, up to 30s)
 * - JSON parsing with JsonUtils.safeParse fallback
 * - Console warnings on first crash only
 * - Graceful degradation when swaync unavailable
 *
 * @example
 * // Basic usage with defaults
 * NotificationModule {}
 *
 * @example
 * // Custom click commands
 * NotificationModule {
 *     onClickCommand: "swaync-client -t"
 *     onRightClickCommand: "swaync-client -d"
 * }
 */
import ".."
import "../components"
import "../components/JsonUtils.js" as JsonUtils
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ModuleContainer {
    id: root

    property color iconColor: Config.m3.primary
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
    property int watchRestartAttempts: 0
    property bool watchDegraded: false

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
                        color: Config.m3.onSurface
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

    Timer {
        id: watchRestartTimer

        interval: Math.min(30000, 1000 * Math.pow(2, root.watchRestartAttempts))
        running: false

        onTriggered: {
            root.watchDegraded = false;
            watchProcess.running = true;
        }
    }
    Timer {
        id: watchBackoffResetTimer

        interval: 60000
        running: watchProcess.running
        repeat: false

        onTriggered: {
            if (root.watchRestartAttempts > 0) {
                console.log("NotificationModule: swaync-client stable for 60s, resetting backoff");
            }
            root.watchRestartAttempts = 0;
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

        onExited: code => {
            if (root.watchRestartAttempts === 0) {
                console.warn(`NotificationModule: swaync-client exited with code ${code}, attempting restart`);
            } else {
                const backoff = Math.min(30000, 1000 * Math.pow(2, root.watchRestartAttempts));
                console.warn(`NotificationModule: swaync-client crashed again (attempt ${root.watchRestartAttempts + 1}), next restart in ${backoff}ms`);
            }
            root.watchDegraded = true;
            root.watchRestartAttempts++;
            watchBackoffResetTimer.stop();
            watchRestartTimer.restart();
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
