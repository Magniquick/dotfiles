pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import Quickshell.Networking
import "../components"

Item {
    id: root
    visible: false

    property int tooltipUserCount: 0
    readonly property bool tooltipActive: root.tooltipUserCount > 0

    property string connectionState: ""
    property string connectionType: "disconnected" // disconnected | wifi | ethernet
    property string deviceName: ""
    property int frequencyMhz: 0
    property string ipAddress: ""
    property string gateway: ""
    property int signalPercent: 0
    property string ssid: ""
    property var sourceEntries: []
    property bool sourceSwitching: false
    property string sourceSwitchingName: ""
    property string sourceError: ""
    readonly property bool nativeNetworkBackend: Networking.backend === NetworkBackendType.NetworkManager
    readonly property var connectedDevice: root.findConnectedDevice()
    readonly property var connectedWifiNetwork: root.findConnectedWifiNetwork()

    // Ethernet/USB NIC details
    property string ethernetSubsystem: ""
    property string ethernetDeviceLabel: ""
    property string lastEthernetDevice: ""
    property bool subsystemCheckRequested: false
    property bool deviceLabelRequested: false

    // Traffic monitoring
    property double rxBytesPerSec: 0
    property double txBytesPerSec: 0
    property var rxHistory: []
    property var txHistory: []
    property real trafficScaleMax: 1024
    property int trafficHistorySize: 60
    property real trafficScaleFloor: 1024
    property double lastRxBytes: 0
    property double lastTxBytes: 0
    property double lastTrafficSampleMs: 0
    property bool trafficBaselineReady: false
    // Traffic sampling can be triggered by multiple paths (initial refresh + timer).
    // Guard against tiny deltas that produce absurd spikes, and smooth rates for a less jittery UI.
    property int minTrafficSampleDeltaMs: 600
    property double trafficEmaAlpha: 0.5

    function addTooltipUser() {
        root.tooltipUserCount = Math.max(0, root.tooltipUserCount + 1);
    }

    function removeTooltipUser() {
        root.tooltipUserCount = Math.max(0, root.tooltipUserCount - 1);
    }

    function refreshNetwork() {
        root.syncNativeState();
        ipAddressRunner.trigger();
        gatewayRunner.trigger();
        root.refreshSources();
        root.readTrafficSample();
        if (root.connectionType === "ethernet" && root.connectionState === "connected") {
            root.subsystemCheckRequested = true;
            ethernetSubsystemRunner.trigger();
            if (root.ethernetSubsystem === "usb")
                ethernetDeviceLabelRunner.trigger();
        }
    }

    function sortSourceEntries(entries) {
        const sorted = entries.slice();
        sorted.sort(function(a, b) {
            if (!!a.active !== !!b.active)
                return a.active ? -1 : 1;
            const aName = String(a.name || "").toLowerCase();
            const bName = String(b.name || "").toLowerCase();
            if (aName < bName)
                return -1;
            if (aName > bName)
                return 1;
            return 0;
        });
        return sorted;
    }

    function modelAt(model, index) {
        if (!model || index < 0)
            return null;
        if (model.values && typeof model.values.length === "number")
            return model.values[index];
        if (typeof model.get === "function")
            return model.get(index);
        return model[index];
    }

    function modelCount(model) {
        if (!model)
            return 0;
        if (model.values && typeof model.values.length === "number")
            return model.values.length;
        if (typeof model.count === "number")
            return model.count;
        if (typeof model.length === "number")
            return model.length;
        return 0;
    }

    function findConnectedDevice() {
        if (!root.nativeNetworkBackend)
            return null;

        const devices = Networking.devices;
        const deviceCount = root.modelCount(devices);
        let fallbackEthernet = null;

        for (let i = 0; i < deviceCount; i++) {
            const device = root.modelAt(devices, i);
            if (!device || !device.connected)
                continue;
            if (device.type === DeviceType.Wifi)
                return device;
            if (!fallbackEthernet)
                fallbackEthernet = device;
        }

        return fallbackEthernet;
    }

    function findConnectedWifiNetwork() {
        const wifiDevice = root.connectedDevice;
        if (!wifiDevice || wifiDevice.type !== DeviceType.Wifi)
            return null;

        const networks = wifiDevice.networks;
        const networkCount = root.modelCount(networks);
        for (let i = 0; i < networkCount; i++) {
            const network = root.modelAt(networks, i);
            if (network && network.connected)
                return network;
        }

        return null;
    }

    function setWifiScannerEnabled(enabled) {
        if (!root.nativeNetworkBackend)
            return;

        const devices = Networking.devices;
        const deviceCount = root.modelCount(devices);
        for (let i = 0; i < deviceCount; i++) {
            const device = root.modelAt(devices, i);
            if (!device || device.type !== DeviceType.Wifi || device.scannerEnabled === enabled)
                continue;
            device.scannerEnabled = enabled;
        }
    }

    function syncNativeState() {
        if (!root.nativeNetworkBackend) {
            root.connectionType = "disconnected";
            root.connectionState = "";
            root.deviceName = "";
            root.ssid = "";
            root.signalPercent = 0;
            root.frequencyMhz = 0;
            root.ethernetSubsystem = "";
            root.ethernetDeviceLabel = "";
            root.lastEthernetDevice = "";
            root.subsystemCheckRequested = false;
            root.deviceLabelRequested = false;
            root.ipAddress = "";
            root.gateway = "";
            root.resetTraffic();
            return;
        }

        const device = root.connectedDevice;
        const wifiNetwork = root.connectedWifiNetwork;
        const nextType = !device
            ? "disconnected"
            : (device.type === DeviceType.Wifi ? "wifi" : "ethernet");
        const nextDeviceName = device ? String(device.name || "") : "";
        const nextSsid = wifiNetwork ? String(wifiNetwork.name || "") : "";
        const nextSignalPercent = wifiNetwork && isFinite(wifiNetwork.signalStrength)
            ? Math.max(0, Math.min(100, Math.round(wifiNetwork.signalStrength * 100)))
            : 0;
        const deviceChanged = root.deviceName !== nextDeviceName;
        const typeChanged = root.connectionType !== nextType;

        root.connectionType = nextType;
        root.connectionState = device ? "connected" : "";
        root.deviceName = nextDeviceName;
        root.ssid = nextSsid;
        root.signalPercent = nextSignalPercent;
        root.frequencyMhz = 0;

        if (deviceChanged || typeChanged) {
            root.ipAddress = "";
            root.gateway = "";
            root.resetTraffic();
        }

        if (nextType !== "ethernet") {
            root.ethernetSubsystem = "";
            root.ethernetDeviceLabel = "";
            root.lastEthernetDevice = "";
            root.subsystemCheckRequested = false;
            root.deviceLabelRequested = false;
        } else {
            const ethernetDeviceChanged = root.lastEthernetDevice !== nextDeviceName;
            root.lastEthernetDevice = nextDeviceName;
            if (ethernetDeviceChanged) {
                root.ethernetSubsystem = "";
                root.ethernetDeviceLabel = "";
                root.deviceLabelRequested = false;
            }
            root.subsystemCheckRequested = root.connectionState === "connected";
        }
    }

    function collectNativeSourceEntries() {
        const entries = [];
        const devices = Networking.devices;
        const deviceCount = root.modelCount(devices);

        for (let i = 0; i < deviceCount; i++) {
            const device = root.modelAt(devices, i);
            if (!device)
                continue;

            const deviceName = String(device.name || "").trim();
            const isWifi = device.type === DeviceType.Wifi;
            if (isWifi) {
                const networks = device.networks;
                const networkCount = root.modelCount(networks);
                for (let j = 0; j < networkCount; j++) {
                    const network = root.modelAt(networks, j);
                    if (!network)
                        continue;
                    const networkName = String(network.name || "").trim();
                    if (networkName === "")
                        continue;
                    const known = network.known === undefined ? true : !!network.known;
                    if (!known && !network.connected)
                        continue;
                    entries.push({
                        id: "wifi:" + deviceName + ":" + networkName,
                        type: "wifi",
                        name: networkName,
                        device: deviceName,
                        active: !!network.connected,
                        connectable: true,
                        network
                    });
                }
                continue;
            }

            if (!!device.connected) {
                entries.push({
                    id: "ethernet:" + deviceName,
                    type: "ethernet",
                    name: "Wired",
                    device: deviceName,
                    active: true,
                    connectable: false
                });
            }
        }

        return entries;
    }

    function refreshSources() {
        if (!root.nativeNetworkBackend) {
            root.sourceEntries = [];
            return;
        }

        const nativeEntries = root.sortSourceEntries(root.collectNativeSourceEntries());
        root.sourceEntries = nativeEntries;
        if (root.sourceSwitching && root.sourceSwitchingName !== "") {
            for (let i = 0; i < nativeEntries.length; i++) {
                const entry = nativeEntries[i];
                if (entry && entry.active && String(entry.name || "") === root.sourceSwitchingName) {
                    root.sourceSwitching = false;
                    root.sourceSwitchingName = "";
                    root.sourceError = "";
                    sourceSwitchTimeoutTimer.stop();
                    break;
                }
            }
        }
    }

    function switchSource(source) {
        const entry = typeof source === "object" ? source : null;
        const name = entry ? String(entry.name || "").trim() : String(source || "").trim();
        if (name === "" || root.sourceSwitching)
            return;
        if (entry && !!entry.active)
            return;

        root.sourceSwitching = true;
        root.sourceSwitchingName = name;
        root.sourceError = "";
        sourceSwitchTimeoutTimer.restart();

        if (entry && entry.network && typeof entry.network.connect === "function") {
            try {
                entry.network.connect();
            } catch (err) {
                root.sourceError = "Unable to switch source";
                root.sourceSwitching = false;
                root.sourceSwitchingName = "";
                sourceSwitchTimeoutTimer.stop();
            }
            return;
        }

        root.sourceError = "Native networking backend unavailable";
        root.sourceSwitching = false;
        root.sourceSwitchingName = "";
        sourceSwitchTimeoutTimer.stop();
    }

    function refreshNativeStateFromSignal() {
        root.syncNativeState();
        if (root.tooltipActive)
            root.refreshSources();
    }

    function applyEthernetSubsystem(subsystem) {
        const cleanedSubsystem = (subsystem || "").trim();
        root.ethernetSubsystem = cleanedSubsystem;
        root.subsystemCheckRequested = false;
        if (root.connectionType !== "ethernet" || root.connectionState !== "connected")
            return;

        if (cleanedSubsystem === "usb") {
            root.deviceLabelRequested = root.ethernetDeviceLabel === "";
            ethernetDeviceLabelRunner.trigger();
        } else {
            root.deviceLabelRequested = false;
        }
    }

    function updateIpAddressDetails(text) {
        let ipValue = "";
        if (!text || text.trim() === "") {
            root.ipAddress = "";
            return;
        }

        try {
            const parsed = JSON.parse(text);
            const entries = Array.isArray(parsed) ? parsed : [];
            for (let i = 0; i < entries.length; i++) {
                const addrInfo = entries[i] && Array.isArray(entries[i].addr_info) ? entries[i].addr_info : [];
                for (let j = 0; j < addrInfo.length; j++) {
                    const item = addrInfo[j] || {};
                    if (item.family === "inet" && item.local) {
                        const prefixlen = Number.isFinite(item.prefixlen) ? item.prefixlen : "";
                        ipValue = String(item.local) + (prefixlen !== "" ? "/" + prefixlen : "");
                        break;
                    }
                }
                if (ipValue !== "")
                    break;
            }
        } catch (err) {
            ipValue = "";
        }

        root.ipAddress = ipValue;
    }

    function updateGatewayDetails(text) {
        let gatewayValue = "";
        if (!text || text.trim() === "") {
            root.gateway = "";
            return;
        }

        try {
            const parsed = JSON.parse(text);
            const entries = Array.isArray(parsed) ? parsed : [];
            for (let i = 0; i < entries.length; i++) {
                const gateway = entries[i] && entries[i].gateway ? String(entries[i].gateway) : "";
                if (gateway !== "") {
                    gatewayValue = gateway;
                    break;
                }
            }
        } catch (err) {
            gatewayValue = "";
        }

        root.gateway = gatewayValue;
    }

    function readTrafficSample() {
        if (!root.deviceName)
            return;
        rxBytesFile.reload();
        txBytesFile.reload();
        const rx = rxBytesFile.text().trim();
        const tx = txBytesFile.text().trim();
        if (!rx || !tx)
            return;

        const rxBytes = parseFloat(rx);
        const txBytes = parseFloat(tx);
        if (!isFinite(rxBytes) || !isFinite(txBytes))
            return;
        root.updateTrafficRates(rxBytes, txBytes, Date.now());
    }

    function resetTraffic() {
        root.rxBytesPerSec = 0;
        root.txBytesPerSec = 0;
        root.lastRxBytes = 0;
        root.lastTxBytes = 0;
        root.lastTrafficSampleMs = 0;
        root.trafficBaselineReady = false;
        root.resetTrafficHistory();
    }

    function resetTrafficHistory() {
        root.rxHistory = [];
        root.txHistory = [];
        root.trafficScaleMax = root.trafficScaleFloor;
    }

    function pushTrafficSample(rxSample, txSample) {
        const rx = isFinite(rxSample) && rxSample > 0 ? rxSample : 0;
        const tx = isFinite(txSample) && txSample > 0 ? txSample : 0;

        const nextRxHistory = root.rxHistory.slice();
        const nextTxHistory = root.txHistory.slice();

        nextRxHistory.push(rx);
        nextTxHistory.push(tx);

        if (nextRxHistory.length > root.trafficHistorySize)
            nextRxHistory.splice(0, nextRxHistory.length - root.trafficHistorySize);
        if (nextTxHistory.length > root.trafficHistorySize)
            nextTxHistory.splice(0, nextTxHistory.length - root.trafficHistorySize);

        root.rxHistory = nextRxHistory;
        root.txHistory = nextTxHistory;

        let peak = root.trafficScaleFloor;
        for (let i = 0; i < nextRxHistory.length; i++)
            peak = Math.max(peak, nextRxHistory[i]);
        for (let j = 0; j < nextTxHistory.length; j++)
            peak = Math.max(peak, nextTxHistory[j]);
        root.trafficScaleMax = peak;
    }

    function applyEma(previous, sample, alpha) {
        if (!isFinite(sample) || sample < 0)
            return 0;
        if (!isFinite(previous) || previous <= 0)
            return sample;
        const a = Math.max(0.01, Math.min(0.99, alpha));
        return previous * (1 - a) + sample * a;
    }

    function updateTrafficRates(rxBytes, txBytes, now) {
        if (!root.trafficBaselineReady || root.lastTrafficSampleMs <= 0 || now <= root.lastTrafficSampleMs) {
            root.rxBytesPerSec = 0;
            root.txBytesPerSec = 0;
            root.lastRxBytes = rxBytes;
            root.lastTxBytes = txBytes;
            root.lastTrafficSampleMs = now;
            root.trafficBaselineReady = true;
            return;
        }

        const deltaMs = now - root.lastTrafficSampleMs;
        if (deltaMs < root.minTrafficSampleDeltaMs) {
            // Too soon since last sample: update baseline but don't recompute rate.
            root.lastRxBytes = rxBytes;
            root.lastTxBytes = txBytes;
            root.lastTrafficSampleMs = now;
            return;
        }

        const deltaSeconds = deltaMs / 1000;
        const rxDelta = rxBytes - root.lastRxBytes;
        const txDelta = txBytes - root.lastTxBytes;
        if (rxDelta >= 0 && txDelta >= 0 && deltaSeconds > 0) {
            const rxInstant = rxDelta / deltaSeconds;
            const txInstant = txDelta / deltaSeconds;
            root.rxBytesPerSec = root.applyEma(root.rxBytesPerSec, rxInstant, root.trafficEmaAlpha);
            root.txBytesPerSec = root.applyEma(root.txBytesPerSec, txInstant, root.trafficEmaAlpha);
            root.pushTrafficSample(root.rxBytesPerSec, root.txBytesPerSec);
        } else {
            root.rxBytesPerSec = 0;
            root.txBytesPerSec = 0;
            root.pushTrafficSample(0, 0);
        }

        root.lastRxBytes = rxBytes;
        root.lastTxBytes = txBytes;
        root.lastTrafficSampleMs = now;
    }

    onTooltipActiveChanged: {
        root.setWifiScannerEnabled(root.tooltipActive);
        if (root.tooltipActive) {
            root.refreshNetwork();
        } else {
            root.resetTraffic();
            root.sourceSwitching = false;
            root.sourceSwitchingName = "";
            sourceSwitchTimeoutTimer.stop();
        }
    }

    Component.onCompleted: {
        root.syncNativeState();
        root.refreshSources();
    }

    CommandRunner {
        id: ipAddressRunner

        // Quickshell.Networking gives us device/network state, but not the
        // active IPv4 address on the current backend.
        command: root.deviceName
            ? ["ip", "-j", "-4", "addr", "show", "dev", root.deviceName, "scope", "global"]
            : []
        enabled: root.tooltipActive
            && root.connectionState === "connected"
            && root.deviceName !== ""
        intervalMs: 30000

        onRan: function(commandOutput) {
            root.updateIpAddressDetails(commandOutput);
        }
    }

    CommandRunner {
        id: gatewayRunner

        // Quickshell.Networking gives us device/network state, but not the
        // default gateway on the current backend.
        command: root.deviceName
            ? ["ip", "-j", "route", "show", "default", "dev", root.deviceName]
            : []
        enabled: root.tooltipActive
            && root.connectionState === "connected"
            && root.deviceName !== ""
        intervalMs: 30000

        onRan: function(commandOutput) {
            root.updateGatewayDetails(commandOutput);
        }
    }

    Connections {
        target: Networking

        function onWifiEnabledChanged() {
            root.refreshNativeStateFromSignal();
        }

        function onWifiHardwareEnabledChanged() {
            root.refreshNativeStateFromSignal();
        }
    }

    Connections {
        target: Networking.devices

        function onObjectInsertedPost(object, index) {
            root.refreshNativeStateFromSignal();
        }

        function onObjectRemovedPost(object, index) {
            root.refreshNativeStateFromSignal();
        }
    }

    Repeater {
        model: root.nativeNetworkBackend ? Networking.devices : null

        delegate: Item {
            id: deviceWatcher

            required property var modelData

            Connections {
                target: deviceWatcher.modelData

                function onConnectedChanged() {
                    root.refreshNativeStateFromSignal();
                }

                function onNameChanged() {
                    root.refreshNativeStateFromSignal();
                }

                function onStateChanged() {
                    root.refreshNativeStateFromSignal();
                }
            }

            Connections {
                target: deviceWatcher.modelData && deviceWatcher.modelData.networks ? deviceWatcher.modelData.networks : null

                function onObjectInsertedPost(object, index) {
                    root.refreshNativeStateFromSignal();
                }

                function onObjectRemovedPost(object, index) {
                    root.refreshNativeStateFromSignal();
                }
            }

            Repeater {
                model: deviceWatcher.modelData && deviceWatcher.modelData.networks ? deviceWatcher.modelData.networks : null

                delegate: Item {
                    id: networkWatcher

                    required property var modelData

                    Connections {
                        target: networkWatcher.modelData

                        function onConnectedChanged() {
                            root.refreshNativeStateFromSignal();
                        }

                        function onKnownChanged() {
                            if (root.tooltipActive)
                                root.refreshSources();
                        }

                        function onStateChanged() {
                            root.refreshNativeStateFromSignal();
                        }

                        function onStateChangingChanged() {
                            root.refreshNativeStateFromSignal();
                        }

                        function onSignalStrengthChanged() {
                            root.refreshNativeStateFromSignal();
                        }
                    }
                }
            }
        }
    }

    FileView {
        id: rxBytesFile
        path: root.deviceName ? "/sys/class/net/" + root.deviceName + "/statistics/rx_bytes" : ""
        blockLoading: true
    }

    FileView {
        id: txBytesFile
        path: root.deviceName ? "/sys/class/net/" + root.deviceName + "/statistics/tx_bytes" : ""
        blockLoading: true
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.tooltipActive
            && root.connectionType === "wifi"
            && root.deviceName !== ""
            && root.connectionState === "connected"
        onTriggered: root.readTrafficSample()
    }

    CommandRunner {
        id: ethernetSubsystemRunner

        // The Networking API does not currently expose sysfs/udev hardware metadata.
        command: root.deviceName
            ? "if [ -L /sys/class/net/" + root.deviceName + "/device/subsystem ]; then basename \"$(readlink /sys/class/net/" + root.deviceName + "/device/subsystem)\"; fi"
            : ""
        enabled: root.connectionType === "ethernet"
            && root.connectionState === "connected"
            && root.deviceName !== ""
            && root.subsystemCheckRequested
        intervalMs: 0

        onRan: function(commandOutput) {
            root.applyEthernetSubsystem(commandOutput);
        }
    }

    CommandRunner {
        id: ethernetDeviceLabelRunner

        // Friendly USB NIC labels still come from udev properties today.
        command: root.deviceName
            ? "if [ -d /sys/class/net/" + root.deviceName + "/device ]; then udevadm info -q property -p /sys/class/net/" + root.deviceName + " | sed -n 's/^ID_MODEL_FROM_DATABASE=//p; s/^ID_MODEL=//p; s/^ID_VENDOR_FROM_DATABASE=//p; s/^ID_VENDOR=//p' | head -n1; fi"
            : ""
        enabled: root.connectionType === "ethernet"
            && root.connectionState === "connected"
            && root.deviceName !== ""
            && root.ethernetSubsystem === "usb"
            && root.deviceLabelRequested
        intervalMs: 0

        onRan: function(commandOutput) {
            const label = (commandOutput || "").trim();
            root.ethernetDeviceLabel = label.replace(/_/g, " ");
            root.deviceLabelRequested = false;
        }
    }

    Timer {
        id: sourceSwitchTimeoutTimer

        interval: 12000
        running: false
        repeat: false

        onTriggered: {
            if (!root.sourceSwitching)
                return;
            root.sourceError = "Switch request timed out";
            root.sourceSwitching = false;
            root.sourceSwitchingName = "";
        }
    }
}
