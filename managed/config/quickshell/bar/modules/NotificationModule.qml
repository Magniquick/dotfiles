/**
 * @module NotificationModule
 * @description Notification status indicator that toggles the right panel
 *
 * Features:
 * - Toggles the right panel on click
 * - Shows bell icon
 *
 * @example
 * // Basic usage
 * NotificationModule {}
 */
pragma ComponentBehavior: Bound
import ".."
import "../components"
import QtQuick

ModuleContainer {
    id: root

    property bool dndEnabled: GlobalState.notificationDnd
    property color iconColor: root.dndEnabled ? Config.color.on_secondary_container : Config.color.primary

    backgroundColor: root.dndEnabled ? Config.color.secondary_container : Config.barModuleBackground

    tooltipText: {
        const count = GlobalState.notificationCount;
        if (count === 1)
            return "1 notification";
        return count + " notifications";
    }
    tooltipTitle: "Notifications"

    content: [
        IconLabel {
            color: root.iconColor
            font.pixelSize: Config.iconSize + Config.spaceHalfXs
            text: root.dndEnabled ? "󰂛" : "󱅫"
        }
    ]

    onClicked: GlobalState.toggleRightPanel()
    onRightClicked: GlobalState.toggleNotificationDnd()
}
