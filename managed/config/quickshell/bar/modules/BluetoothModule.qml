pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import ".."
import "../components"

ModuleContainer {
    id: root
    property string iconOff: "󰂲"
    property string iconOn: "󰂰"
    property string iconDisabled: "󰂱"
    property string iconConnected: ""
    property string onClickCommand: "runapp kitty -o tab_bar_style=hidden --class bluetui -e 'bluetui'"

    readonly property var bluetooth: Bluetooth

    property var adapter: bluetooth.defaultAdapter
    property var devices: bluetooth.devices ? bluetooth.devices.values : []
    property var activeDevice: devices.length > 0 ? devices[0] : null
    property var deviceSnapshot: []
    property int pairedCount: 0
    property int connectedCount: 0
    property string connectedNames: ""
    property var connectedDevice: null
    property int connectedBattery: -1
    property string adapterName: ""

    tooltipTitle: root.connectedNames !== "" ? root.connectedNames : "Bluetooth"
    tooltipText: ""
    tooltipHoverable: true
    tooltipContent: Component {
        ColumnLayout {
            spacing: Config.space.md
            width: 240

            // Header Section
            RowLayout {
                Layout.fillWidth: true
                spacing: Config.space.md

                Item {
                    Layout.preferredWidth: Config.space.xxl * 2
                    Layout.preferredHeight: Config.space.xxl * 2

                    Text {
                        anchors.centerIn: parent
                        text: root.displayText()
                        font.pixelSize: Config.type.headlineLarge.size
                        color: root.stateColor()
                    }
                }

                ColumnLayout {
                    spacing: Config.space.none
                    Text {
                        text: root.connectedNames !== "" ? root.connectedNames : (root.adapterName !== "" ? root.adapterName : "Bluetooth")
                        color: Config.textColor
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.headlineSmall.size
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: root.statusLabel()
                        color: Config.textMuted
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.labelMedium.size
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            ProgressBar {
                Layout.fillWidth: true
                Layout.preferredHeight: Config.space.xs
                visible: root.connectedBattery >= 0
                value: root.connectedBattery / 100
                fillColor: Config.green
                trackColor: Config.moduleBackgroundMuted
            }

            // Details Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.xs

                Text {
                    text: "BLUETOOTH DETAILS"
                    color: Config.primary
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.labelSmall.size
                    font.weight: Font.Black
                    font.letterSpacing: 1.5
                    Layout.bottomMargin: Config.space.xs
                }

                InfoRow {
                    label: "Adapter"
                    value: root.adapterName
                    visible: root.adapterName !== ""
                    Layout.fillWidth: true
                }
                InfoRow {
                    label: "Status"
                    value: root.statusLabel()
                    Layout.fillWidth: true
                }
                InfoRow {
                    label: "Paired Devices"
                    value: root.pairedCount.toString()
                    Layout.fillWidth: true
                }
            }

            // Metrics Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.xs

                Text {
                    text: "DEVICES"
                    color: Config.primary
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.labelSmall.size
                    font.weight: Font.Black
                    font.letterSpacing: 1.5
                    Layout.bottomMargin: Config.space.xs
                }

                RowLayout {
                    spacing: Config.space.sm
                    Layout.fillWidth: true

                    MetricBlock {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        label: "Connected"
                        value: root.connectedCount.toString()
                        icon: root.iconConnected
                        accentColor: Config.green
                        borderWidth: 0
                        showFill: false
                    }

                    MetricBlock {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        label: "Total"
                        value: root.devices.length.toString()
                        icon: root.iconOn
                        accentColor: Config.lavender
                        borderWidth: 0
                        showFill: false
                    }
                }
            }

            TooltipActionsRow {
                spacing: Config.space.sm
                ActionChip {
                    text: "Open Settings"
                    onClicked: Quickshell.execDetached(["sh", "-c", root.onClickCommand])
                    Layout.fillWidth: true
                }

                ActionChip {
                    text: "Refresh"
                    onClicked: root.refreshBluetooth()
                    Layout.fillWidth: true
                }
            }
        }
    }

    function stateColor() {
        if (!adapter)
            return Config.textMuted;
        if (!adapter.enabled)
            return Config.textMuted;
        if (connectedCount > 0)
            return Config.lavender;
        return Config.textColor;
    }

    function statusLabel() {
        if (!adapter)
            return "Off";
        if (!adapter.enabled)
            return "Disabled";
        return connectedCount > 0 ? "Connected" : "On";
    }

    function deviceLabel(device) {
        if (!device)
            return "";
        return device.alias || device.name || device.address || "";
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

    function displayText() {
        if (!adapter || !adapter.enabled)
            return root.iconOff;
        return root.connectedCount > 0 ? root.iconConnected : root.iconOn;
    }

    content: [
        IconLabel {
            text: root.displayText()
            color: root.stateColor()
        }
    ]

    MouseArea {
        anchors.fill: parent
        onClicked: Quickshell.execDetached(["sh", "-c", root.onClickCommand])
    }

    onTooltipActiveChanged: {
        if (root.tooltipActive)
            root.refreshBluetooth();
    }

    onDevicesChanged: {
        if (root.tooltipActive)
            root.refreshBluetooth();
    }

    onAdapterChanged: {
        if (root.tooltipActive)
            root.refreshBluetooth();
    }
}
