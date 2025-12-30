pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import ".."
import "../components"

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
            return Config.m3.onSurfaceVariant;
        if (!adapter.enabled)
            return Config.m3.onSurfaceVariant;
        if (connectedCount > 0)
            return Config.m3.tertiary;
        return Config.m3.onSurface;
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
            RowLayout {
                Layout.fillWidth: true
                spacing: Config.space.md

                Item {
                    Layout.preferredHeight: Config.space.xxl * 2
                    Layout.preferredWidth: Config.space.xxl * 2

                    Text {
                        anchors.centerIn: parent
                        color: root.stateColor()
                        font.pixelSize: Config.type.headlineLarge.size
                        text: root.displayText()
                    }
                }
                ColumnLayout {
                    spacing: Config.space.none

                    Text {
                        Layout.fillWidth: true
                        color: Config.m3.onSurface
                        elide: Text.ElideRight
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.headlineSmall.size
                        font.weight: Font.Bold
                        text: root.connectedNames !== "" ? root.connectedNames : (root.adapterName !== "" ? root.adapterName : "Bluetooth")
                    }
                    Text {
                        color: Config.m3.onSurfaceVariant
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.labelMedium.size
                        text: root.statusLabel()
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
            }
            ProgressBar {
                Layout.fillWidth: true
                Layout.preferredHeight: Config.space.xs
                fillColor: Config.m3.success
                trackColor: Config.moduleBackgroundMuted
                value: root.connectedBattery / 100
                visible: root.connectedBattery >= 0
            }

            // Details Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.xs

                Text {
                    Layout.bottomMargin: Config.space.xs
                    color: Config.m3.primary
                    font.family: Config.fontFamily
                    font.letterSpacing: 1.5
                    font.pixelSize: Config.type.labelSmall.size
                    font.weight: Font.Black
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

                Text {
                    Layout.bottomMargin: Config.space.xs
                    color: Config.m3.primary
                    font.family: Config.fontFamily
                    font.letterSpacing: 1.5
                    font.pixelSize: Config.type.labelSmall.size
                    font.weight: Font.Black
                    text: "DEVICES"
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Config.space.sm

                    MetricBlock {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        accentColor: Config.m3.success
                        borderWidth: 0
                        icon: root.iconConnected
                        label: "Connected"
                        showFill: false
                        value: root.connectedCount.toString()
                    }
                    MetricBlock {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        accentColor: Config.m3.tertiary
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

                    onClicked: Quickshell.execDetached(["sh", "-c", root.onClickCommand])
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

    MouseArea {
        anchors.fill: parent

        onClicked: Quickshell.execDetached(["sh", "-c", root.onClickCommand])
    }
}
