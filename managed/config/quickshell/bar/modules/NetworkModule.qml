pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../components"

ModuleContainer {
    id: root

    property string connectionState: ""
    property string connectionType: "disconnected"
    property bool deviceLabelRequested: false
    property string deviceName: ""
    property string disconnectedIcon: "󰖪"
    property string ethernetConnection: ""
    property string ethernetDeviceLabel: ""
    property string ethernetIcon: "󰈀"
    property string ethernetSubsystem: ""
    property bool forceRefreshRequested: false
    property int frequencyMhz: 0
    property string gateway: ""
    property string iconText: "󰖪"
    property string ipAddress: ""
    property string lastEthernetDevice: ""
    property double lastRxBytes: 0
    property double lastTrafficSampleMs: 0
    property double lastTxBytes: 0
    property string linkedIcon: "󰤣"
    property bool needsInitialRefresh: true
    property string onClickCommand: "runapp nmgui"
    readonly property bool pollingActive: root.tooltipActive || root.needsInitialRefresh
    property double rxBytesPerSec: 0
    property int signalPercent: 0
    property string ssid: ""
    property bool subsystemCheckRequested: false
    readonly property double trafficPeak: Math.max(1, Math.max(root.rxBytesPerSec, root.txBytesPerSec))
    property double txBytesPerSec: 0
    property string usbEthernetIcon: ""
    property var wifiIcons: ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]

    function applyEthernetStatus(ethernetLine) {
        if (!ethernetLine)
            return false;
        const parts = ethernetLine.split(":");
        const device = parts[0] || "";
        const deviceChanged = root.lastEthernetDevice !== device;
        root.lastEthernetDevice = device;
        root.deviceName = device;
        if (deviceChanged)
            root.ethernetSubsystem = "";
        if (deviceChanged) {
            root.ethernetDeviceLabel = "";
            root.deviceLabelRequested = false;
        }
        const connection = parts.slice(3).join(":");
        root.ethernetConnection = connection && connection !== "--" ? connection : "";
        root.connectionType = "ethernet";
        root.connectionState = parts[2] || "";
        if (deviceChanged || root.connectionState !== "connected")
            root.subsystemCheckRequested = true;
        if (root.connectionState !== "connected") {
            root.subsystemCheckRequested = false;
            root.deviceLabelRequested = false;
        }
        if (root.connectionState === "connected") {
            root.clearWifiDetails();
            root.iconText = root.ethernetIcon;
            ethernetSubsystemRunner.trigger();
            return true;
        }
        if (root.connectionState === "connected (externally)")
            root.iconText = root.linkedIcon;
        return false;
    }
    function applyEthernetSubsystem(subsystem) {
        const cleanedSubsystem = (subsystem || "").trim();
        root.ethernetSubsystem = cleanedSubsystem;
        root.subsystemCheckRequested = false;
        if (root.connectionType !== "ethernet" || root.connectionState !== "connected")
            return;
        root.iconText = cleanedSubsystem === "usb" ? root.usbEthernetIcon : root.ethernetIcon;
        if (cleanedSubsystem === "usb") {
            root.deviceLabelRequested = root.ethernetDeviceLabel === "";
            ethernetDeviceLabelRunner.trigger();
        } else {
            root.deviceLabelRequested = false;
        }
    }
    function applyWifiStatus(wifiLine, wasWifiConnected) {
        if (!wifiLine)
            return false;
        const parts = wifiLine.split(":");
        root.deviceName = parts[0] || "";
        root.connectionType = "wifi";
        root.connectionState = parts[2] || "";
        root.subsystemCheckRequested = false;
        root.deviceLabelRequested = false;
        const connection = parts.slice(3).join(":");
        root.ssid = connection && connection !== "--" ? connection : "";
        if (root.connectionState === "connected") {
            if (!wasWifiConnected)
                root.resetTraffic();
            ipRunner.trigger();
            trafficRunner.trigger();
            root.iconText = root.iconForSignal();
            return true;
        }
        return false;
    }
    function clearWifiDetails() {
        root.ssid = "";
        root.signalPercent = 0;
        root.frequencyMhz = 0;
        root.ipAddress = "";
        root.gateway = "";
        root.resetTraffic();
    }
    function connectionLabel() {
        if (root.connectionType === "wifi")
            return root.connectionState === "connected" ? "Wi-Fi connected" : "Wi-Fi disconnected";
        if (root.connectionType === "ethernet") {
            if (root.connectionState === "connected (externally)")
                return root.ethernetDescription() + " linked";
            return root.connectionState === "connected" ? root.ethernetDescription() + " connected" : root.ethernetDescription() + " disconnected";
        }
        return "Offline";
    }
    function ethernetDescription() {
        return root.ethernetDeviceLabel !== "" ? root.ethernetDeviceLabel : root.ethernetLabel();
    }
    function ethernetLabel() {
        return root.ethernetSubsystem === "usb" ? "USB Ethernet" : "Ethernet";
    }
    function findStatusLines(lines) {
        let wifiLine = "";
        let ethernetLine = "";
        for (let i = 0; i < lines.length; i++) {
            if (lines[i].indexOf(":wifi:") > 0)
                wifiLine = lines[i];
            else if (lines[i].indexOf(":ethernet:") > 0)
                ethernetLine = lines[i];
        }
        return {
            wifiLine: wifiLine,
            ethernetLine: ethernetLine
        };
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
    function handleNetworkManagerEvent(data) {
        if (!data || data.trim() === "")
            return;
        root.subsystemCheckRequested = true;
        root.forceRefreshRequested = true;
        root.refreshNetwork();
    }
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
    function parseIpDetails(lines) {
        let ipValue = "";
        let gatewayValue = "";
        for (let i = 0; i < lines.length; i++) {
            const parts = lines[i].split(":");
            const key = parts[0];
            const value = parts.slice(1).join(":");
            if (key.indexOf("IP4.ADDRESS") === 0 && !ipValue)
                ipValue = value;
            else if (key === "IP4.GATEWAY")
                gatewayValue = value;
        }
        return {
            ipAddress: ipValue,
            gateway: gatewayValue
        };
    }
    function parseTrafficBytes(lines) {
        if (lines.length < 2)
            return {
                valid: false,
                rxBytes: NaN,
                txBytes: NaN
            };
        const rxBytes = parseFloat(lines[0]);
        const txBytes = parseFloat(lines[1]);
        if (!isFinite(rxBytes) || !isFinite(txBytes))
            return {
                valid: false,
                rxBytes: NaN,
                txBytes: NaN
            };
        return {
            valid: true,
            rxBytes: rxBytes,
            txBytes: txBytes
        };
    }
    function parseWifiSignal(lines) {
        let signalValue = 0;
        let ssidValue = "";
        let frequencyValue = 0;
        for (let i = 0; i < lines.length; i++) {
            const parts = lines[i].split(":");
            if (parts[0] === "yes") {
                signalValue = parseInt(parts[1] || "0", 10);
                ssidValue = parts[2] || "";
                frequencyValue = parseInt(parts[3] || "0", 10);
                break;
            }
        }
        return {
            signalPercent: isNaN(signalValue) ? 0 : signalValue,
            ssid: ssidValue,
            frequencyMhz: isNaN(frequencyValue) ? 0 : frequencyValue
        };
    }
    function refreshNetwork() {
        statusRunner.trigger();
        wifiRunner.trigger();
        ipRunner.trigger();
        trafficRunner.trigger();
        if (root.connectionType === "ethernet" && root.connectionState === "connected") {
            root.subsystemCheckRequested = true;
            ethernetSubsystemRunner.trigger();
            if (root.ethernetSubsystem === "usb")
                ethernetDeviceLabelRunner.trigger();
        }
    }
    function resetTraffic() {
        root.rxBytesPerSec = 0;
        root.txBytesPerSec = 0;
        root.lastRxBytes = 0;
        root.lastTxBytes = 0;
        root.lastTrafficSampleMs = 0;
    }
    function speedText() {
        if (root.rxBytesPerSec <= 0 && root.txBytesPerSec <= 0)
            return "";
        return "↑ " + root.formatRate(root.txBytesPerSec) + " ↓ " + root.formatRate(root.rxBytesPerSec);
    }
    function updateIpDetails(text) {
        if (!text || text.trim() === "") {
            root.ipAddress = "";
            root.gateway = "";
            return;
        }
        const details = root.parseIpDetails(text.trim().split("\n"));
        root.ipAddress = details.ipAddress;
        root.gateway = details.gateway;
    }
    function updateSignal(text) {
        if (!text)
            return;
        const details = root.parseWifiSignal(text.trim().split("\n"));
        root.signalPercent = details.signalPercent;
        if (details.ssid)
            root.ssid = details.ssid;
        root.frequencyMhz = details.frequencyMhz;
        if (root.connectionType === "wifi" && root.connectionState === "connected")
            root.iconText = root.iconForSignal();
    }
    function updateStatus(text) {
        if (!text)
            return;
        root.forceRefreshRequested = false;
        root.needsInitialRefresh = false;
        const wasWifiConnected = root.connectionType === "wifi" && root.connectionState === "connected";
        const lines = text.trim().split("\n");
        const statusLines = root.findStatusLines(lines);
        if (root.applyWifiStatus(statusLines.wifiLine, wasWifiConnected))
            return;
        if (root.applyEthernetStatus(statusLines.ethernetLine))
            return;
        root.connectionType = "disconnected";
        root.connectionState = "";
        root.iconText = root.disconnectedIcon;
        root.deviceName = "";
        root.ethernetSubsystem = "";
        root.ethernetDeviceLabel = "";
        root.ethernetConnection = "";
        root.lastEthernetDevice = "";
        root.subsystemCheckRequested = false;
        root.deviceLabelRequested = false;
        root.clearWifiDetails();
    }
    function updateTraffic(text) {
        if (!text || text.trim() === "")
            return;
        const parsed = root.parseTrafficBytes(text.trim().split("\n"));
        if (!parsed.valid)
            return;
        root.updateTrafficRates(parsed.rxBytes, parsed.txBytes, Date.now());
    }
    function updateTrafficRates(rxBytes, txBytes, now) {
        if (root.lastTrafficSampleMs > 0 && now > root.lastTrafficSampleMs) {
            const deltaSeconds = (now - root.lastTrafficSampleMs) / 1000;
            const rxDelta = rxBytes - root.lastRxBytes;
            const txDelta = txBytes - root.lastTxBytes;
            if (rxDelta >= 0 && txDelta >= 0 && deltaSeconds > 0) {
                root.rxBytesPerSec = rxDelta / deltaSeconds;
                root.txBytesPerSec = txDelta / deltaSeconds;
            } else {
                root.rxBytesPerSec = 0;
                root.txBytesPerSec = 0;
            }
        }
        root.lastRxBytes = rxBytes;
        root.lastTxBytes = txBytes;
        root.lastTrafficSampleMs = now;
    }

    tooltipHoverable: true
    tooltipText: ""
    tooltipTitle: root.connectionType === "wifi" ? "Wi-Fi" : (root.connectionType === "ethernet" ? root.ethernetLabel() : "Ethernet")

    content: [
        IconLabel {
            color: root.connectionState === "connected" ? Config.flamingo : Config.textMuted
            text: root.iconText
        }
    ]
    tooltipContent: Component {
        ColumnLayout {
            id: menu

            readonly property int maxMenuWidth: 520
            readonly property int menuWidth: Math.min(menu.maxMenuWidth, Math.max(menu.minMenuWidth, headerRow.implicitWidth))
            readonly property int minMenuWidth: 240

            implicitWidth: menu.menuWidth
            spacing: Config.space.md
            width: menu.menuWidth

            // Header Section
            RowLayout {
                id: headerRow

                Layout.fillWidth: true
                spacing: Config.space.md

                Item {
                    Layout.preferredHeight: Config.space.xxl * 2
                    Layout.preferredWidth: Config.space.xxl * 2

                    Text {
                        anchors.centerIn: parent
                        color: root.connectionState === "connected" ? Config.flamingo : Config.textMuted
                        font.pixelSize: Config.type.headlineLarge.size
                        text: root.iconText
                    }
                }
                ColumnLayout {
                    spacing: Config.space.none

                    Text {
                        id: connectionTitleText

                        Layout.fillWidth: true
                        color: Config.textColor
                        elide: Text.ElideRight
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.headlineSmall.size
                        font.weight: Font.Bold
                        text: root.connectionType === "wifi" ? (root.ssid !== "" ? root.ssid : "Wi-Fi") : (root.connectionType === "ethernet" ? root.ethernetLabel() : "Disconnected")
                    }
                    Text {
                        id: connectionSubtitleText

                        color: Config.textMuted
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.labelMedium.size
                        text: root.connectionLabel()
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
            }
            ProgressBar {
                Layout.fillWidth: true
                Layout.preferredHeight: Config.space.xs
                fillColor: Config.flamingo
                trackColor: Config.moduleBackgroundMuted
                value: root.signalPercent / 100
                visible: root.connectionType === "wifi" && root.connectionState === "connected"
            }

            // Details Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.xs

                Text {
                    Layout.bottomMargin: Config.space.xs
                    color: Config.primary
                    font.family: Config.fontFamily
                    font.letterSpacing: 1.5
                    font.pixelSize: Config.type.labelSmall.size
                    font.weight: Font.Black
                    text: "NETWORK DETAILS"
                }
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

            // Traffic Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.xs
                visible: root.connectionState === "connected"

                Text {
                    Layout.bottomMargin: Config.space.xs
                    color: Config.primary
                    font.family: Config.fontFamily
                    font.letterSpacing: 1.5
                    font.pixelSize: Config.type.labelSmall.size
                    font.weight: Font.Black
                    text: "TRAFFIC"
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Config.space.sm

                    MetricBlock {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        accentColor: Config.pink
                        borderWidth: 0
                        icon: "󰕒"
                        label: "Up"
                        showFill: false
                        value: root.formatRate(root.txBytesPerSec)
                    }
                    MetricBlock {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        accentColor: Config.green
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

                    onClicked: Quickshell.execDetached(["sh", "-c", root.onClickCommand])
                }
                ActionChip {
                    Layout.fillWidth: true
                    text: "Refresh"

                    onClicked: root.refreshNetwork()
                }
            }
        }
    }

    onTooltipActiveChanged: {
        if (root.tooltipActive) {
            root.refreshNetwork();
        } else {
            root.resetTraffic();
        }
    }

    CommandRunner {
        id: statusRunner

        command: "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev status"
        enabled: root.pollingActive || root.forceRefreshRequested
        intervalMs: 5000

        onOutputChanged: root.updateStatus(output)
    }
    CommandRunner {
        id: wifiRunner

        command: "nmcli -t -f ACTIVE,SIGNAL,SSID,FREQ dev wifi"
        enabled: root.pollingActive || root.forceRefreshRequested
        intervalMs: 7000

        onOutputChanged: root.updateSignal(output)
    }
    CommandRunner {
        id: ipRunner

        command: root.deviceName ? "nmcli -t -f IP4.ADDRESS,IP4.GATEWAY dev show " + root.deviceName : ""
        enabled: root.tooltipActive && root.connectionType === "wifi" && root.connectionState === "connected" && root.deviceName !== ""
        intervalMs: 12000

        onOutputChanged: root.updateIpDetails(output)
    }
    CommandRunner {
        id: trafficRunner

        command: root.deviceName ? "cat /sys/class/net/" + root.deviceName + "/statistics/rx_bytes /sys/class/net/" + root.deviceName + "/statistics/tx_bytes" : ""
        enabled: root.tooltipActive && root.connectionType === "wifi" && root.connectionState === "connected" && root.deviceName !== ""
        intervalMs: 1000

        onOutputChanged: root.updateTraffic(output)
    }
    CommandRunner {
        id: ethernetSubsystemRunner

        command: root.deviceName ? "if [ -L /sys/class/net/" + root.deviceName + "/device/subsystem ]; then basename \"$(readlink /sys/class/net/" + root.deviceName + "/device/subsystem)\"; fi" : ""
        enabled: (root.connectionType === "ethernet" && root.connectionState === "connected" && root.deviceName !== "") && (root.subsystemCheckRequested || root.forceRefreshRequested)
        intervalMs: 0

        onOutputChanged: root.applyEthernetSubsystem(output)
    }
    CommandRunner {
        id: ethernetDeviceLabelRunner

        command: root.deviceName ? "if [ -d /sys/class/net/" + root.deviceName + "/device ]; then udevadm info -q property -p /sys/class/net/" + root.deviceName + " | sed -n 's/^ID_MODEL_FROM_DATABASE=//p; s/^ID_MODEL=//p; s/^ID_VENDOR_FROM_DATABASE=//p; s/^ID_VENDOR=//p' | head -n1; fi" : ""
        enabled: (root.connectionType === "ethernet" && root.connectionState === "connected" && root.deviceName !== "" && root.ethernetSubsystem === "usb") && (root.deviceLabelRequested || root.forceRefreshRequested)
        intervalMs: 0

        onOutputChanged: {
            const label = (output || "").trim();
            root.ethernetDeviceLabel = label.replace(/_/g, " ");
            root.deviceLabelRequested = false;
        }
    }
    Process {
        id: networkManagerMonitor

        command: ["nmcli", "monitor"]
        running: true

        stdout: SplitParser {
            onRead: function (data) {
                root.handleNetworkManagerEvent(data);
            }
        }
    }
    MouseArea {
        anchors.fill: parent

        onClicked: Quickshell.execDetached(["sh", "-c", root.onClickCommand])
    }
}
