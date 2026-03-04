/**
 * @module BluetoothModule
 * @description Bluetooth status and device management module
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import ".."
import "../components"
import "../../common" as Common

ModuleContainer {
    id: root

    readonly property var bluetooth: Bluetooth
    property var adapter: bluetooth.defaultAdapter
    property var devices: adapter && adapter.devices ? adapter.devices.values : []
    property var deviceSnapshot: []

    property string iconConnected: ""
    property string iconDisabled: "󰂲"
    property string iconOn: "󰂯"
    property string iconOff: "󰂲"
    property string iconScanning: "󰂰"
    property string onClickCommand: "runapp kitty -o tab_bar_style=hidden --class bluetui -e 'bluetui'"

    property int connectedCount: 0
    property int connectedBattery: -1
    property string connectedNames: ""
    property bool detailsExpanded: false
    property string pendingDeviceKey: ""
    property bool pendingConnect: false
    property bool scanActive: false
    property bool debugLogging: true

    readonly property bool adapterEnabled: !!(root.adapter && root.adapter.enabled)
    readonly property bool adapterDiscovering: !!(root.adapter && root.adapter.discovering)
    readonly property string adapterName: root.adapter && root.adapter.name ? String(root.adapter.name) : "Bluetooth"

    function logDebug(message) {
        if (!root.debugLogging)
            return;
        console.log("[BluetoothModule]", new Date().toISOString(), message);
    }

    function deviceLabel(device) {
        if (!device)
            return "";
        return device.alias || device.name || device.address || "Unknown device";
    }

    function deviceKey(device) {
        if (!device)
            return "";
        return device.dbusPath || device.address || root.deviceLabel(device);
    }

    function deviceBatteryValue(device) {
        if (!device)
            return -1;
        if (Number.isFinite(device.batteryPercentage))
            return Math.max(0, Math.min(100, Math.round(device.batteryPercentage)));
        if (Number.isFinite(device.battery))
            return Math.max(0, Math.min(100, Math.round(device.battery)));
        return -1;
    }

    function deviceStateLabel(device) {
        if (!device)
            return "Unknown";

        const key = root.deviceKey(device);
        if (root.pendingDeviceKey === key)
            return root.pendingConnect ? "Connecting" : "Disconnecting";

        if (device.connected)
            return "Connected";

        if (device.state !== undefined && device.state !== null) {
            try {
                const txt = BluetoothDeviceState.toString(device.state);
                if (txt && txt.length > 0)
                    return txt;
            } catch (error) {
            }
        }

        if (device.paired)
            return "Paired";

        return "Available";
    }

    function statusLabel() {
        if (!root.adapter)
            return "Unavailable";
        if (!root.adapterEnabled)
            return "Disabled";
        if (root.scanActive)
            return "Scanning";
        if (root.connectedCount > 0)
            return "Connected";
        return "Ready";
    }

    function stateColor() {
        if (!root.adapter || !root.adapterEnabled)
            return Config.color.on_surface_variant;
        if (root.connectedCount > 0)
            return Config.color.tertiary;
        if (root.adapterDiscovering)
            return Config.color.primary;
        return Config.color.on_surface;
    }

    function displayIcon() {
        if (!root.adapter)
            return root.iconDisabled;
        if (!root.adapterEnabled)
            return root.iconOff;
        if (root.connectedCount > 0)
            return root.iconConnected;
        if (root.scanActive)
            return root.iconScanning;
        return root.iconOn;
    }

    function sortedDevices(list) {
        const copy = (list || []).slice(0);
        copy.sort((a, b) => {
            const aConnected = a && a.connected ? 1 : 0;
            const bConnected = b && b.connected ? 1 : 0;
            if (aConnected !== bConnected)
                return bConnected - aConnected;

            const aPaired = a && a.paired ? 1 : 0;
            const bPaired = b && b.paired ? 1 : 0;
            if (aPaired !== bPaired)
                return bPaired - aPaired;

            const aLabel = root.deviceLabel(a).toLowerCase();
            const bLabel = root.deviceLabel(b).toLowerCase();
            if (aLabel < bLabel)
                return -1;
            if (aLabel > bLabel)
                return 1;
            return 0;
        });
        return copy;
    }

    function refreshBluetooth() {
        const list = root.sortedDevices(root.devices || []);
        root.deviceSnapshot = list;

        root.connectedCount = 0;
        root.connectedBattery = -1;

        const names = [];
        for (let i = 0; i < list.length; i++) {
            const device = list[i];
            if (!device)
                continue;

            if (device.connected) {
                root.connectedCount += 1;
                const label = root.deviceLabel(device);
                if (label.length > 0)
                    names.push(label);

                if (root.connectedBattery < 0)
                    root.connectedBattery = root.deviceBatteryValue(device);
            }
        }

        root.connectedNames = names.join(", ");

        if (root.pendingDeviceKey.length > 0) {
            const pendingStillExists = list.some(device => root.deviceKey(device) === root.pendingDeviceKey);
            if (!pendingStillExists)
                root.pendingDeviceKey = "";
        }

        root.requestScanState();
    }

    function toggleAdapterEnabled() {
        if (!root.adapter)
            return;
        root.adapter.enabled = !root.adapter.enabled;
        if (!root.adapter.enabled)
            root.refreshBluetooth();
    }

    function setDiscovery(active) {
        if (!root.adapter || !root.adapterEnabled)
            return;

        root.logDebug("setDiscovery(" + active + ") requested; adapterDiscovering=" + root.adapterDiscovering + " scanActive=" + root.scanActive);

        // Avoid noisy BlueZ warnings when stop is requested but discovery is already off.
        if (root.adapterDiscovering === active) {
            root.scanActive = active;
            root.logDebug("setDiscovery early-return (already in requested state)");
            return;
        }

        root.scanActive = active;
        root.adapter.discovering = active;
        root.logDebug("adapter.discovering set to " + active + "; now adapterDiscovering=" + root.adapterDiscovering);

        // BlueZ sometimes ignores a stale stop/start; issue a best-effort CLI fallback.
        Common.ProcessHelper.execDetached(["bluetoothctl", "scan", active ? "on" : "off"]);
        root.logDebug("fallback bluetoothctl scan " + (active ? "on" : "off") + " dispatched");

        refreshTimer.restart();
        scanRefreshTimer.restart();
    }

    function toggleDiscovery() {
        const currentlyScanning = root.scanActive || root.adapterDiscovering;
        root.logDebug("toggleDiscovery currentlyScanning=" + currentlyScanning + " (scanActive=" + root.scanActive + ", adapterDiscovering=" + root.adapterDiscovering + ")");
        root.setDiscovery(!currentlyScanning);
    }

    function toggleDeviceConnection(device) {
        if (!device || !root.adapterEnabled)
            return;

        const connectTarget = !device.connected;
        root.pendingDeviceKey = root.deviceKey(device);
        root.pendingConnect = connectTarget;

        try {
            if (connectTarget)
                device.connect();
            else
                device.disconnect();
        } catch (error) {
            try {
                device.connected = connectTarget;
            } catch (innerError) {
            }
        }

        if (device.address && device.address.length > 0)
            Common.ProcessHelper.execDetached(["bluetoothctl", connectTarget ? "connect" : "disconnect", device.address]);

        refreshTimer.restart();
    }

    function openSettings() {
        Common.ProcessHelper.execDetached(root.onClickCommand);
    }

    Timer {
        id: refreshTimer
        interval: 1000
        repeat: false
        onTriggered: {
            root.pendingDeviceKey = "";
            root.refreshBluetooth();
        }
    }

    function requestScanState() {
        if (!root.adapterEnabled) {
            root.scanActive = false;
            root.logDebug("requestScanState skipped (adapter disabled)");
            return;
        }
        if (scanStateProcess.running) {
            root.logDebug("requestScanState skipped (probe already running)");
            return;
        }
        root.logDebug("requestScanState starting bluetoothctl show probe");
        scanStateProcess.running = true;
    }

    Process {
        id: scanStateProcess
        command: ["bluetoothctl", "show"]

        stdout: StdioCollector {
            onStreamFinished: {
                const match = this.text.match(/Discovering:\s*(yes|no)/i);
                if (!match) {
                    root.logDebug("scan probe parse failed; output=" + JSON.stringify(this.text));
                    return;
                }
                root.scanActive = match[1].toLowerCase() === "yes";
                root.logDebug("scan probe parsed discovering=" + root.scanActive);
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const err = String(this.text || "").trim();
                if (err.length > 0)
                    root.logDebug("scan probe stderr: " + err);
            }
        }

        onExited: code => root.logDebug("scan probe exited code=" + code)
    }

    Timer {
        id: scanPollTimer
        interval: 2000
        repeat: true
        running: root.tooltipActive && root.adapterEnabled
        onTriggered: root.requestScanState()
    }

    Timer {
        id: scanRefreshTimer
        interval: 500
        repeat: false
        onTriggered: root.requestScanState()
    }

    tooltipHoverable: true
    tooltipText: ""
    tooltipTitle: root.connectedNames !== "" ? root.connectedNames : root.adapterName

    content: [
        IconLabel {
            color: root.stateColor()
            text: root.displayIcon()
        }
    ]

    tooltipContent: Component {
        ColumnLayout {
            id: menu

            readonly property int maxVisibleRows: 5
            readonly property int rowHeight: 46
            readonly property int rowsShown: Math.min(maxVisibleRows, root.deviceSnapshot.length)
            readonly property int rowsHeight: rowsShown > 0
                ? (rowsShown * rowHeight) + ((rowsShown - 1) * Config.space.xs)
                : 0

            spacing: Config.space.md
            width: 276

            RowLayout {
                id: headerRow

                Layout.fillWidth: true
                spacing: Config.space.md

                Item {
                    Layout.preferredHeight: Config.space.xxl * 2
                    Layout.preferredWidth: Config.space.xxl * 2

                    Rectangle {
                        anchors.centerIn: parent
                        color: Qt.alpha(root.stateColor(), 0.12)
                        height: parent.height
                        radius: height / 2
                        width: parent.width
                    }

                    Text {
                        anchors.centerIn: parent
                        color: root.stateColor()
                        font.pixelSize: Config.type.headlineLarge.size
                        text: root.displayIcon()
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitHeight: headerContent.implicitHeight

                    ColumnLayout {
                        id: headerContent
                        anchors.fill: parent
                        spacing: Config.space.none

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Config.space.xs

                            Text {
                                Layout.minimumWidth: 0
                                color: Config.color.on_surface
                                elide: Text.ElideRight
                                font.family: Config.fontFamily
                                font.pixelSize: Config.type.headlineSmall.size
                                font.weight: Font.Bold
                                text: root.connectedNames !== "" ? root.connectedNames : root.adapterName
                            }

                            Text {
                                color: Config.color.on_surface_variant
                                font.family: Config.iconFontFamily
                                font.pixelSize: Config.type.labelLarge.size
                                text: root.detailsExpanded ? "󰅀" : "󰅂"
                            }

                            Item { Layout.fillWidth: true }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            color: Config.color.on_surface_variant
                            elide: Text.ElideRight
                            font.family: Config.fontFamily
                            font.pixelSize: Config.type.labelMedium.size
                            text: root.statusLabel()
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.detailsExpanded = !root.detailsExpanded
                    }
                }
            }

            ProgressBar {
                Layout.fillWidth: true
                Layout.preferredHeight: Config.space.xs
                fillColor: Config.color.tertiary
                trackColor: Config.color.surface_variant
                value: root.connectedBattery / 100
                visible: root.connectedBattery >= 0
            }

            StackLayout {
                Layout.fillWidth: true
                currentIndex: root.detailsExpanded ? 1 : 0

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Config.space.xs
                    visible: root.deviceSnapshot.length > 0

                    SectionHeader {
                        text: "DEVICES"
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: menu.rowsHeight
                        clip: true
                        visible: menu.rowsShown > 0

                        ListView {
                            anchors.fill: parent
                            boundsBehavior: Flickable.StopAtBounds
                            boundsMovement: Flickable.StopAtBounds
                            clip: true
                            flickableDirection: Flickable.VerticalFlick
                            interactive: root.deviceSnapshot.length > menu.maxVisibleRows
                            model: root.deviceSnapshot
                            spacing: Config.space.xs

                            delegate: Rectangle {
                                required property var modelData

                                readonly property var device: modelData
                                readonly property int battery: root.deviceBatteryValue(device)
                                readonly property bool connected: !!(device && device.connected)
                                readonly property string stateText: root.deviceStateLabel(device)

                                width: ListView.view ? ListView.view.width : parent.width
                                height: menu.rowHeight
                                radius: Config.shape.corner.md
                                color: connected
                                    ? Qt.alpha(Config.color.primary_container, 0.45)
                                    : Config.color.surface_container_high
                                border.width: 1
                                border.color: connected
                                    ? Qt.alpha(Config.color.primary, 0.5)
                                    : Qt.alpha(Config.color.outline_variant, 0.75)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Config.space.sm
                                    anchors.rightMargin: Config.space.sm
                                    spacing: Config.space.sm

                                    Text {
                                        color: connected ? Config.color.primary : Config.color.on_surface_variant
                                        font.family: Config.iconFontFamily
                                        font.pixelSize: Config.type.labelLarge.size
                                        text: connected ? "" : "󰂯"
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: Config.space.none

                                        Text {
                                            Layout.fillWidth: true
                                            color: Config.color.on_surface
                                            elide: Text.ElideRight
                                            font.family: Config.fontFamily
                                            font.pixelSize: Config.type.bodyLarge.size
                                            font.weight: Config.type.bodyLarge.weight
                                            text: root.deviceLabel(device)
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            color: Config.color.on_surface_variant
                                            elide: Text.ElideRight
                                            font.family: Config.fontFamily
                                            font.pixelSize: Config.type.labelMedium.size
                                            text: battery >= 0
                                                ? (stateText + " • " + battery.toString() + "%")
                                                : stateText
                                        }
                                    }

                                    Text {
                                        color: Config.color.on_surface_variant
                                        font.family: Config.iconFontFamily
                                        font.pixelSize: Config.type.labelLarge.size
                                        text: connected ? "󰅖" : "󰐕"
                                    }
                                }

                                HybridRipple {
                                    anchors.fill: parent
                                    color: connected ? Config.color.on_primary_container : Config.color.on_surface
                                    pressX: rowMouseArea.pressX
                                    pressY: rowMouseArea.pressY
                                    pressed: rowMouseArea.pressed
                                    radius: parent.radius
                                    stateLayerEnabled: false
                                    stateOpacity: 0
                                }

                                MouseArea {
                                    id: rowMouseArea
                                    property real pressX: width / 2
                                    property real pressY: height / 2

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleDeviceConnection(device)
                                    onPressed: function(mouse) {
                                        pressX = mouse.x;
                                        pressY = mouse.y;
                                    }
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Config.space.xs

                    SectionHeader { text: "BLUETOOTH DETAILS" }

                    InfoRow {
                        Layout.fillWidth: true
                        label: "Adapter"
                        value: root.adapterName
                    }

                    InfoRow {
                        Layout.fillWidth: true
                        label: "Status"
                        value: root.statusLabel()
                    }

                    InfoRow {
                        Layout.fillWidth: true
                        label: "Connected Devices"
                        value: root.connectedCount.toString()
                    }

                    InfoRow {
                        Layout.fillWidth: true
                        label: "Scanning"
                        value: root.scanActive ? "Yes" : "No"
                        visible: !!root.adapter
                    }
                }
            }

            TooltipActionsRow {
                spacing: Config.space.sm

                ActionChip {
                    Layout.fillWidth: true
                    text: root.adapterEnabled ? "Turn Off" : "Turn On"
                    onClicked: root.toggleAdapterEnabled()
                }

                ActionChip {
                    Layout.fillWidth: true
                    enabled: root.adapterEnabled
                    text: (root.scanActive || root.adapterDiscovering) ? "Stop Scan" : "Scan"
                    onClicked: root.toggleDiscovery()
                }
            }

            TooltipActionsRow {
                spacing: Config.space.sm

                ActionChip {
                    Layout.fillWidth: true
                    text: "Open Settings"
                    onClicked: root.openSettings()
                }

                ActionChip {
                    Layout.fillWidth: true
                    text: "Refresh"
                    onClicked: root.refreshBluetooth()
                }
            }
        }
    }

    onAdapterChanged: root.refreshBluetooth()
    onDevicesChanged: root.refreshBluetooth()
    onAdapterDiscoveringChanged: {
        root.logDebug("onAdapterDiscoveringChanged -> " + root.adapterDiscovering);
        root.scanActive = root.adapterDiscovering;
        root.requestScanState();
    }
    onTooltipActiveChanged: {
        if (root.tooltipActive) {
            root.refreshBluetooth();
            root.requestScanState();
        }
    }

    onClicked: root.openSettings()

    Component.onCompleted: root.refreshBluetooth()
}
