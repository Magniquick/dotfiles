/**
 * @module ArchIconModule
 * @description Arch Linux icon button
 *
 * Features:
 * - Displays Arch Linux icon in bar
 * - Left click opens sidebar, right click opens powermenu
 */
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import ".."
import "../components"

ModuleContainer {
    id: root

    property string iconText: "󰣇"

    content: [
        IconLabel {
            antialiasing: true
            color: Config.color.tertiary
            renderType: Text.NativeRendering
            text: root.iconText
        }
    ]

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
                Quickshell.execDetached(["quickshell", "--path", Quickshell.env("HOME") + "/.config/quickshell/powermenu/"]);
            } else {
                GlobalState.toggleLeftPanel();
            }
        }
    }
}
