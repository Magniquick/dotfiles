/**
 * @module IdleInhibitModule
 * @description Toggle idle inhibition for the bar window.
 *
 * Usage:
 * IdleInhibitModule { targetWindow: parentWindow }
 */
pragma ComponentBehavior: Bound
import ".."
import "../components"
import QtQuick
import Quickshell.Wayland

ModuleContainer {
    id: root

    property bool inhibitEnabled: false
    property var targetWindow: null
    readonly property string iconText: root.inhibitEnabled ? "󰒳" : "󰒲"
    readonly property color iconColor: root.inhibitEnabled ? Config.color.on_primary_container : Config.color.on_surface

    backgroundColor: root.inhibitEnabled ? Config.color.primary_container : Config.barModuleBackground
    tooltipTitle: "Idle Inhibit"
    tooltipText: root.inhibitEnabled ? "On" : "Off"
    tooltipSubtitle: root.inhibitEnabled ? "Screen will stay awake" : "Screen may idle"

    onClicked: root.inhibitEnabled = !root.inhibitEnabled

    IdleInhibitor {
        enabled: root.inhibitEnabled
        window: root.targetWindow
    }

    content: [
        IconLabel {
            color: root.iconColor
            text: root.iconText
        }
    ]
}
