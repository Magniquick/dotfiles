pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import Quickshell.Networking
import ".."
import "../components"
import "network/Parsers.js" as Parsers

Item {
    id: root
    visible: false

    property bool nmcliAvailable: false

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

    // Ethernet/USB NIC details
    property string ethernetConnection: ""
    property string ethernetSubsystem: ""
    property string ethernetDeviceLabel: ""
    property string lastEthernetDevice: ""
    property bool subsystemCheckRequested: false
    property bool deviceLabelRequested: false
    property bool forceRefreshRequested: false

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
    // Traffic sampling can be triggered by multiple paths (initial refresh + nmcli status output + timer).
    // Guard against tiny deltas that produce absurd spikes, and smooth rates for a less jittery UI.
    property int minTrafficSampleDeltaMs: 600
    property double trafficEmaAlpha: 0.5

    // Polling/monitor debounce and caching
    property bool needsInitialRefresh: true
    readonly property bool pollingActive: root.tooltipActive || root.needsInitialRefresh
    property double lastMonitorEventMs: 0
    property int monitorDebounceMs: 300
    property double lastStatusUpdateMs: 0
    property int statusCacheMs: 30000

    function addTooltipUser() {
        root.tooltipUserCount = Math.max(0, root.tooltipUserCount + 1);
    }

    function removeTooltipUser() {
        root.tooltipUserCount = Math.max(0, root.tooltipUserCount - 1);
    }

    function refreshNetwork() {
        statusRunner.trigger();
        wifiRunner.trigger();
        ipRunner.trigger();
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

    function handleNetworkManagerEvent(data) {
        if (!data || data.trim() === "")
            return;

        const now = Date.now();
        if (now - root.lastMonitorEventMs < root.monitorDebounceMs)
            return;

        root.lastMonitorEventMs = now;
        root.subsystemCheckRequested = true;

        if (root.tooltipActive) {
            monitorDebouncedRefresh.restart();
            return;
        }

        const cacheAge = now - root.lastStatusUpdateMs;
        if (cacheAge < root.statusCacheMs && root.lastStatusUpdateMs > 0)
            return;

        root.forceRefreshRequested = true;
        monitorDebouncedRefresh.restart();
    }

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
            ethernetSubsystemRunner.trigger();
            return true;
        }

        return false;
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
            root.readTrafficSample();
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

    function updateStatus(text) {
        if (!text)
            return;
        root.forceRefreshRequested = false;
        root.needsInitialRefresh = false;
        root.lastStatusUpdateMs = Date.now();

        const wasWifiConnected = root.connectionType === "wifi" && root.connectionState === "connected";
        const lines = text.trim().split("\n");
        const statusLines = Parsers.findStatusLines(lines);
        if (root.applyWifiStatus(statusLines.wifiLine, wasWifiConnected))
            return;
        if (root.applyEthernetStatus(statusLines.ethernetLine))
            return;

        root.connectionType = "disconnected";
        root.connectionState = "";
        root.deviceName = "";
        root.ethernetSubsystem = "";
        root.ethernetDeviceLabel = "";
        root.ethernetConnection = "";
        root.lastEthernetDevice = "";
        root.subsystemCheckRequested = false;
        root.deviceLabelRequested = false;
        root.clearWifiDetails();
    }

    function updateSignal(text) {
        if (!text)
            return;
        const details = Parsers.parseWifiSignal(text.trim().split("\n"));
        root.signalPercent = details.signalPercent;
        if (details.ssid)
            root.ssid = details.ssid;
        root.frequencyMhz = details.frequencyMhz;
    }

    function updateIpDetails(text) {
        if (!text || text.trim() === "") {
            root.ipAddress = "";
            root.gateway = "";
            return;
        }
        const details = Parsers.parseIpDetails(text.trim().split("\n"));
        root.ipAddress = details.ipAddress;
        root.gateway = details.gateway;
    }

    function updateTraffic(text) {
        if (!text || text.trim() === "")
            return;
        const parsed = Parsers.parseTrafficBytes(text.trim().split("\n"));
        if (!parsed.valid)
            return;
        root.updateTrafficRates(parsed.rxBytes, parsed.txBytes, Date.now());
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
        root.updateTraffic(rx + "\n" + tx);
    }

    function resetTraffic() {
        root.rxBytesPerSec = 0;
        root.txBytesPerSec = 0;
        root.lastRxBytes = 0;
        root.lastTxBytes = 0;
        root.lastTrafficSampleMs = 0;
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
        if (root.lastTrafficSampleMs > 0 && now > root.lastTrafficSampleMs) {
            const deltaMs = (now - root.lastTrafficSampleMs);
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
        } else if (root.lastTrafficSampleMs <= 0) {
            root.pushTrafficSample(0, 0);
        }
        root.lastRxBytes = rxBytes;
        root.lastTxBytes = txBytes;
        root.lastTrafficSampleMs = now;
    }

    onTooltipActiveChanged: {
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
        DependencyCheck.require("nmcli", "NetworkService", function (available) {
            root.nmcliAvailable = available;
        });
    }

    CommandRunner {
        id: statusRunner

        command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "dev", "status"]
        enabled: root.nmcliAvailable && root.pollingActive
        intervalMs: 10000

        onRan: function(commandOutput) {
            root.updateStatus(commandOutput);
        }
    }

    CommandRunner {
        id: wifiRunner

        command: ["nmcli", "-t", "-f", "ACTIVE,SIGNAL,SSID,FREQ", "dev", "wifi"]
        enabled: root.nmcliAvailable
            && root.pollingActive
            && (root.needsInitialRefresh || root.connectionType === "wifi")
        intervalMs: 15000

        onRan: function(commandOutput) {
            root.updateSignal(commandOutput);
        }
    }

    CommandRunner {
        id: ipRunner

        command: root.deviceName ? ["nmcli", "-t", "-f", "IP4.ADDRESS,IP4.GATEWAY", "dev", "show", root.deviceName] : []
        enabled: root.nmcliAvailable
            && root.tooltipActive
            && root.connectionType === "wifi"
            && root.connectionState === "connected"
            && root.deviceName !== ""
        intervalMs: 30000

        onRan: function(commandOutput) {
            root.updateIpDetails(commandOutput);
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.tooltipActive && root.nativeNetworkBackend

        onTriggered: root.refreshSources()
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
            && root.connectionState === "connected"
            && root.deviceName !== ""
        onTriggered: root.readTrafficSample()
    }

    CommandRunner {
        id: ethernetSubsystemRunner

        command: root.deviceName
            ? "if [ -L /sys/class/net/" + root.deviceName + "/device/subsystem ]; then basename \"$(readlink /sys/class/net/" + root.deviceName + "/device/subsystem)\"; fi"
            : ""
        enabled: root.connectionType === "ethernet"
            && root.connectionState === "connected"
            && root.deviceName !== ""
            && (root.subsystemCheckRequested || root.forceRefreshRequested)
        intervalMs: 0

        onRan: function(commandOutput) {
            root.applyEthernetSubsystem(commandOutput);
        }
    }

    CommandRunner {
        id: ethernetDeviceLabelRunner

        command: root.deviceName
            ? "if [ -d /sys/class/net/" + root.deviceName + "/device ]; then udevadm info -q property -p /sys/class/net/" + root.deviceName + " | sed -n 's/^ID_MODEL_FROM_DATABASE=//p; s/^ID_MODEL=//p; s/^ID_VENDOR_FROM_DATABASE=//p; s/^ID_VENDOR=//p' | head -n1; fi"
            : ""
        enabled: root.connectionType === "ethernet"
            && root.connectionState === "connected"
            && root.deviceName !== ""
            && root.ethernetSubsystem === "usb"
            && (root.deviceLabelRequested || root.forceRefreshRequested)
        intervalMs: 0

        onRan: function(commandOutput) {
            const label = (commandOutput || "").trim();
            root.ethernetDeviceLabel = label.replace(/_/g, " ");
            root.deviceLabelRequested = false;
        }
    }

    Timer {
        id: monitorDebouncedRefresh

        interval: root.monitorDebounceMs
        running: false

        onTriggered: {
            statusRunner.trigger();
            root.forceRefreshRequested = false;
        }
    }

    ProcessMonitor {
        command: ["nmcli", "monitor"]
        enabled: root.nmcliAvailable
        onOutput: data => root.handleNetworkManagerEvent(data)
    }
}
