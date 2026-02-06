/**
 * @module BluetoothModule
 * @description Bluetooth status and device management module
 *
 * Features:
 * - Adapter status display (on/off/connected)
 * - Connected device battery level
 * - Paired and connected device counts
 * - Click opens bluetui settings
 *
 * Dependencies:
 * - Quickshell.Bluetooth: Bluetooth adapter and device info
 * - bluetui: Terminal Bluetooth manager (optional, for settings)
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import ".."
import "../components"
import "../../common" as Common

ModuleContainer {
    id: root

    property var activeDevice: devices.length > 0 ? devices[0] : null
    property var adapter: bluetooth.defaultAdapter
    property string adapterName: ""
    readonly property var bluetooth: Bluetooth
    property int connectedBattery: -1
    property int connectedCount: 0
    property var connectedDevice: null
    property string connectedNames: ""
    property var deviceSnapshot: []
    property var devices: bluetooth.devices ? bluetooth.devices.values : []
    property string iconConnected: ""
    property string iconDisabled: "󰂱"
    property string iconOff: "󰂲"
    property string iconOn: "󰂰"
    property string onClickCommand: "runapp kitty -o tab_bar_style=hidden --class bluetui -e 'bluetui'"
    property int pairedCount: 0

    function deviceLabel(device) {
        if (!device)
            return "";
        return device.alias || device.name || device.address || "";
    }
    function displayText() {
        if (!adapter || !adapter.enabled)
            return root.iconOff;
        return root.connectedCount > 0 ? root.iconConnected : root.iconOn;
    }
    function refreshBluetooth() {
        const list = root.devices || [];
        root.deviceSnapshot = list.slice(0);
        root.pairedCount = 0;
        root.connectedCount = 0;
        root.connectedDevice = null;
        root.connectedBattery = -1;
        root.connectedNames = "";
        const names = [];
        for (let i = 0; i < list.length; i++) {
            const device = list[i];
            if (!device)
                continue;
            if (device.paired)
                root.pairedCount += 1;
            if (device.connected) {
                root.connectedCount += 1;
                if (!root.connectedDevice)
                    root.connectedDevice = device;
                const label = root.deviceLabel(device);
                if (label)
                    names.push(label);
                if (root.connectedBattery < 0) {
                    const battery = Number.isFinite(device.batteryPercentage) ? Math.round(device.batteryPercentage) : (Number.isFinite(device.battery) ? Math.round(device.battery) : -1);
                    if (battery >= 0)
                        root.connectedBattery = battery;
                }
            }
        }
        root.connectedNames = names.join(", ");
        root.adapterName = adapter && adapter.name ? adapter.name : "";
    }
    function stateColor() {
        if (!adapter)
            return Config.color.on_surface_variant;
        if (!adapter.enabled)
            return Config.color.on_surface_variant;
        if (connectedCount > 0)
            return Config.color.tertiary;
        return Config.color.on_surface;
    }
    function statusLabel() {
        if (!adapter)
            return "Off";
        if (!adapter.enabled)
            return "Disabled";
        return connectedCount > 0 ? "Connected" : "On";
    }

    tooltipHoverable: true
    tooltipText: ""
    tooltipTitle: root.connectedNames !== "" ? root.connectedNames : "Bluetooth"

    content: [
        IconLabel {
            color: root.stateColor()
            text: root.displayText()
        }
    ]
    tooltipContent: Component {
        ColumnLayout {
            spacing: Config.space.md
            width: 240

            // Header Section
            TooltipHeader {
                icon: root.displayText()
                iconColor: root.stateColor()
                subtitle: root.statusLabel()
                title: root.connectedNames !== "" ? root.connectedNames : (root.adapterName !== "" ? root.adapterName : "Bluetooth")
            }
            ProgressBar {
                Layout.fillWidth: true
                Layout.preferredHeight: Config.space.xs
                fillColor: Config.color.tertiary
                trackColor: Config.color.surface_variant
                value: root.connectedBattery / 100
                visible: root.connectedBattery >= 0
            }

            // Details Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.xs

                SectionHeader {
                    text: "BLUETOOTH DETAILS"
                }
                InfoRow {
                    Layout.fillWidth: true
                    label: "Adapter"
                    value: root.adapterName
                    visible: root.adapterName !== ""
                }
                InfoRow {
                    Layout.fillWidth: true
                    label: "Status"
                    value: root.statusLabel()
                }
                InfoRow {
                    Layout.fillWidth: true
                    label: "Paired Devices"
                    value: root.pairedCount.toString()
                }
            }

            // Metrics Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.xs

                SectionHeader {
                    text: "DEVICES"
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Config.space.sm

                    MetricBlock {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        accentColor: Config.color.tertiary
                        borderWidth: 0
                        icon: root.iconConnected
                        label: "Connected"
                        showFill: false
                        value: root.connectedCount.toString()
                    }
                    MetricBlock {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        accentColor: Config.color.tertiary
                        borderWidth: 0
                        icon: root.iconOn
                        label: "Total"
                        showFill: false
                        value: root.devices.length.toString()
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

                    onClicked: root.refreshBluetooth()
                }
            }
        }
    }

    onAdapterChanged: {
        if (root.tooltipActive)
            root.refreshBluetooth();
    }
    onDevicesChanged: {
        if (root.tooltipActive)
            root.refreshBluetooth();
    }
    onTooltipActiveChanged: {
        if (root.tooltipActive)
            root.refreshBluetooth();
    }

    onClicked: Common.ProcessHelper.execDetached(root.onClickCommand)
}
