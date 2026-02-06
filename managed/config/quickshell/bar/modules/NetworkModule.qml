/**
 * @module NetworkModule
 * @description Presentational network module backed by `NetworkService`.
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../../common" as Common

ModuleContainer {
    id: root

    property string disconnectedIcon: "󰖪"
    property string ethernetIcon: "󰈀"
    property string linkedIcon: "󰤣"
    property string usbEthernetIcon: ""
    property var wifiIcons: ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
    property string onClickCommand: "runapp nmgui"

    readonly property string connectionState: NetworkService.connectionState
    readonly property string connectionType: NetworkService.connectionType
    readonly property string deviceName: NetworkService.deviceName
    readonly property int frequencyMhz: NetworkService.frequencyMhz
    readonly property string gateway: NetworkService.gateway
    readonly property string ipAddress: NetworkService.ipAddress
    readonly property bool nmcliAvailable: NetworkService.nmcliAvailable
    readonly property double rxBytesPerSec: NetworkService.rxBytesPerSec
    readonly property int signalPercent: NetworkService.signalPercent
    readonly property string ssid: NetworkService.ssid
    readonly property double txBytesPerSec: NetworkService.txBytesPerSec
    readonly property string ethernetSubsystem: NetworkService.ethernetSubsystem
    readonly property string ethernetDeviceLabel: NetworkService.ethernetDeviceLabel

    property bool _tooltipHeld: false

    function iconForSignal() {
        const percent = root.signalPercent;
        if (percent <= 0)
            return root.wifiIcons[0];
        if (percent < 25)
            return root.wifiIcons[1];
        if (percent < 50)
            return root.wifiIcons[2];
        if (percent < 75)
            return root.wifiIcons[3];
        return root.wifiIcons[4];
    }

    function formatFrequency(mhz) {
        if (!mhz || mhz <= 0)
            return "";
        const ghz = mhz / 1000;
        return ghz.toFixed(1) + " GHz";
    }

    function formatRate(bytesPerSecond) {
        if (!bytesPerSecond || bytesPerSecond <= 0)
            return "0B/s";
        const units = ["B/s", "KB/s", "MB/s", "GB/s"];
        let value = bytesPerSecond;
        let unitIndex = 0;
        while (value >= 1024 && unitIndex < units.length - 1) {
            value /= 1024;
            unitIndex += 1;
        }
        const decimals = value >= 100 ? 0 : 1;
        return value.toFixed(decimals) + units[unitIndex];
    }

    function ethernetLabel() {
        return root.ethernetSubsystem === "usb" ? "USB Ethernet" : "Ethernet";
    }

    function ethernetDescription() {
        return root.ethernetDeviceLabel !== "" ? root.ethernetDeviceLabel : root.ethernetLabel();
    }

    function connectionLabel() {
        if (!root.nmcliAvailable)
            return "nmcli not available";

        if (root.connectionType === "wifi")
            return root.connectionState === "connected" ? "Wi-Fi connected" : "Wi-Fi disconnected";
        if (root.connectionType === "ethernet") {
            if (root.connectionState === "connected (externally)")
                return root.ethernetDescription() + " linked";
            return root.connectionState === "connected" ? root.ethernetDescription() + " connected" : root.ethernetDescription() + " disconnected";
        }
        return "Offline";
    }

    function connectionIcon() {
        if (!root.nmcliAvailable)
            return root.disconnectedIcon;

        if (root.connectionType === "wifi") {
            if (root.connectionState === "connected")
                return root.iconForSignal();
            return root.disconnectedIcon;
        }
        if (root.connectionType === "ethernet") {
            if (root.connectionState === "connected")
                return root.ethernetSubsystem === "usb" ? root.usbEthernetIcon : root.ethernetIcon;
            if (root.connectionState === "connected (externally)")
                return root.linkedIcon;
            return root.ethernetIcon;
        }
        return root.disconnectedIcon;
    }

    tooltipHoverable: true
    tooltipText: ""
    tooltipTitle: root.connectionType === "wifi" ? "Wi-Fi" : (root.connectionType === "ethernet" ? root.ethernetLabel() : "Ethernet")

    content: [
        IconLabel {
            color: root.connectionState === "connected" ? Config.color.tertiary : Config.color.on_surface_variant
            text: root.connectionIcon()
        }
    ]

    tooltipContent: Component {
        ColumnLayout {
            id: menu

            readonly property int maxMenuWidth: 520
            readonly property int minMenuWidth: 240
            readonly property int menuWidth: Math.min(menu.maxMenuWidth, Math.max(menu.minMenuWidth, headerRow.implicitWidth))

            implicitWidth: menu.menuWidth
            spacing: Config.space.md
            width: menu.menuWidth

            TooltipHeader {
                id: headerRow
                icon: root.connectionIcon()
                iconColor: root.connectionState === "connected" ? Config.color.tertiary : Config.color.on_surface_variant
                subtitle: root.connectionLabel()
                title: root.connectionType === "wifi"
                    ? (root.ssid !== "" ? root.ssid : "Wi-Fi")
                    : (root.connectionType === "ethernet" ? root.ethernetLabel() : "Disconnected")
            }

            ProgressBar {
                Layout.fillWidth: true
                Layout.preferredHeight: Config.space.xs
                fillColor: Config.color.tertiary
                trackColor: Config.color.surface_variant
                value: root.signalPercent / 100
                visible: root.connectionType === "wifi" && root.connectionState === "connected"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.xs

                SectionHeader { text: "NETWORK DETAILS" }

                InfoRow {
                    Layout.fillWidth: true
                    label: "Device"
                    value: root.deviceName
                    visible: root.deviceName !== ""
                }
                InfoRow {
                    Layout.fillWidth: true
                    label: "IP Address"
                    value: root.ipAddress
                    visible: root.ipAddress !== ""
                }
                InfoRow {
                    Layout.fillWidth: true
                    label: "Gateway"
                    value: root.gateway
                    visible: root.gateway !== ""
                }
                InfoRow {
                    Layout.fillWidth: true
                    label: "Frequency"
                    value: root.formatFrequency(root.frequencyMhz)
                    visible: root.connectionType === "wifi" && root.frequencyMhz > 0
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.xs
                visible: root.connectionState === "connected"

                SectionHeader { text: "TRAFFIC" }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Config.space.sm

                    MetricBlock {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        accentColor: Config.color.secondary
                        borderWidth: 0
                        icon: "󰕒"
                        label: "Up"
                        showFill: false
                        value: root.formatRate(root.txBytesPerSec)
                    }
                    MetricBlock {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        accentColor: Config.color.tertiary
                        borderWidth: 0
                        icon: "󰇚"
                        label: "Down"
                        showFill: false
                        value: root.formatRate(root.rxBytesPerSec)
                    }
                }
            }

            TooltipActionsRow {
                spacing: Config.space.sm

                ActionChip {
                    Layout.fillWidth: true
                    text: "Open Settings"
                    onClicked: Common.ProcessHelper.execDetached(root.onClickCommand)
                }
                ActionChip {
                    Layout.fillWidth: true
                    text: "Refresh"
                    onClicked: NetworkService.refreshNetwork()
                }
            }
        }
    }

    onTooltipActiveChanged: {
        if (root.tooltipActive && !root._tooltipHeld) {
            root._tooltipHeld = true;
            NetworkService.addTooltipUser();
        } else if (!root.tooltipActive && root._tooltipHeld) {
            root._tooltipHeld = false;
            NetworkService.removeTooltipUser();
        }
    }

    Component.onDestruction: {
        if (root._tooltipHeld) {
            root._tooltipHeld = false;
            NetworkService.removeTooltipUser();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Common.ProcessHelper.execDetached(root.onClickCommand)
    }
}

