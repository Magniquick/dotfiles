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

    property color iconColor: Config.color.primary

    tooltipText: "Click to open notifications"
    tooltipTitle: "Notifications"

    content: [
        IconLabel {
            color: root.iconColor
            font.pixelSize: Config.iconSize + Config.spaceHalfXs
            text: "󱅫"
        }
    ]

    MouseArea {
        anchors.fill: parent
        onClicked: GlobalState.toggleRightPanel()
    }
}
