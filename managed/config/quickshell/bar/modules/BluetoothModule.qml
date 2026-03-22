/**
 * @module BluetoothModule
 * @description Bluetooth status and device management module
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
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
    property int librepodsBattery: -1
    property int librepodsBatteryLeft: -1
    property int librepodsBatteryRight: -1
    property int librepodsBatteryCase: -1
    property string connectedNames: ""
    property bool detailsExpanded: false
    property string pendingDeviceKey: ""
    property bool pendingConnect: false
    property bool scanActive: false
    property bool moduleScanSession: false
    property bool desiredScanState: false
    property int scanEnsureAttempts: 0
    property string lastScanSource: ""
    property string lastScanAction: "none"
    property string lastStartDiscoverySender: ""
    property int lastStartDiscoveryPid: -1
    property string lastStartDiscoveryProcess: ""
    property string lastScanHolders: ""
    property int lastScanStopNotifyMs: 0
    property bool showUnpairedDevices: false
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
        const alias = String(device.alias || "").trim();
        const name = String(device.name || "").trim();
        if (root.isReadableDeviceName(alias, device))
            return alias;
        if (root.isReadableDeviceName(name, device))
            return name;
        return "";
    }

    function normalizeId(text) {
        return String(text || "").trim().toUpperCase().replace(/[^0-9A-F]/g, "");
    }

    function isRawBluetoothId(text, device) {
        const value = String(text || "").trim();
        if (value.length === 0)
            return true;

        const normalized = root.normalizeId(value);
        const addressNormalized = root.normalizeId(device && device.address ? device.address : "");
        if (addressNormalized.length === 12 && normalized === addressNormalized)
            return true;

        return false;
    }

    function isReadableDeviceName(text, device) {
        const value = String(text || "").trim();
        if (value.length === 0)
            return false;
        if (root.isRawBluetoothId(value, device))
            return false;
        if (value.toLowerCase() === "unknown device")
            return false;
        return true;
    }

    function deviceTypeIcon(device) {
        if (!device)
            return "󰂯";

        const iconName = String(device.icon || "").toLowerCase();
        if (iconName.indexOf("headset") >= 0)
            return "󰋎";
        if (iconName.indexOf("headphone") >= 0)
            return "󰋋";
        if (iconName.indexOf("audio") >= 0 || iconName.indexOf("speaker") >= 0)
            return "󰓃";
        if (iconName.indexOf("phone") >= 0)
            return "󰄜";
        if (iconName.indexOf("keyboard") >= 0)
            return "󰌌";
        if (iconName.indexOf("mouse") >= 0)
            return "󰍽";
        if (iconName.indexOf("gamepad") >= 0 || iconName.indexOf("joystick") >= 0)
            return "󰊗";
        if (iconName.indexOf("tablet") >= 0)
            return "󰓷";
        if (iconName.indexOf("camera") >= 0)
            return "󰄀";
        if (iconName.indexOf("watch") >= 0)
            return "󰋋";
        if (iconName.indexOf("computer") >= 0 || iconName.indexOf("laptop") >= 0)
            return "󰌢";

        return "󰂯";
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

    function parseLibrepodsTooltip(text) {
        const parsed = root.parseLibrepodsTooltipParts(text);
        return parsed.average;
    }

    function parseLibrepodsTooltipParts(text) {
        const raw = String(text || "");
        const m = raw.match(/L:\s*([0-9-]+)%?\s+R:\s*([0-9-]+)%?\s+C:\s*([0-9-]+)/i);
        if (!m)
            return {
                left: -1,
                right: -1,
                caseBattery: -1,
                average: -1
            };

        const values = [];
        const parsedValues = [];
        for (let i = 1; i <= 3; i++) {
            const n = parseInt(m[i], 10);
            if (Number.isFinite(n) && n > 0 && n <= 100) {
                values.push(n);
                parsedValues.push(n);
            } else {
                parsedValues.push(-1);
            }
        }
        if (values.length === 0)
            return {
                left: parsedValues[0],
                right: parsedValues[1],
                caseBattery: parsedValues[2],
                average: -1
            };

        const sum = values.reduce((acc, v) => acc + v, 0);
        return {
            left: parsedValues[0],
            right: parsedValues[1],
            caseBattery: parsedValues[2],
            average: Math.round(sum / values.length)
        };
    }

    function isAirpodsDevice(device) {
        const label = root.deviceLabel(device).toLowerCase();
        return label.indexOf("airpods") >= 0;
    }

    function displayBatteryValue(device, directBattery) {
        if (Number.isFinite(directBattery) && directBattery > 0)
            return directBattery;
        if (!!(device && device.connected) && root.isAirpodsDevice(device) && root.librepodsBattery > 0)
            return root.librepodsBattery;
        return -1;
    }

    function librepodsBatterySummary() {
        if (root.librepodsBatteryLeft <= 0 && root.librepodsBatteryRight <= 0 && root.librepodsBatteryCase <= 0)
            return "";

        const parts = [];
        if (root.librepodsBatteryLeft > 0)
            parts.push("L " + root.librepodsBatteryLeft.toString() + "%");
        if (root.librepodsBatteryRight > 0)
            parts.push("R " + root.librepodsBatteryRight.toString() + "%");
        if (root.librepodsBatteryCase > 0)
            parts.push("C " + root.librepodsBatteryCase.toString() + "%");
        return parts.join(" ");
    }

    function deviceBatterySuffix(device, directBattery) {
        if (Number.isFinite(directBattery) && directBattery > 0)
            return directBattery.toString() + "%";
        if (!!(device && device.connected) && root.isAirpodsDevice(device)) {
            const summary = root.librepodsBatterySummary();
            if (summary.length > 0)
                return summary;
        }
        return "";
    }

    function statusLabel() {
        if (!root.adapter)
            return "Unavailable";
        if (!root.adapterEnabled)
            return "Disabled";
        if (root.moduleScanSession || root.desiredScanState)
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
        if (root.moduleScanSession || root.desiredScanState)
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
        const list = root.sortedDevices((root.devices || []).filter(device => root.deviceLabel(device).length > 0));
        root.deviceSnapshot = list;

        root.connectedCount = 0;
        root.connectedBattery = -1;
        let hasAirpodsConnected = false;

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
                if (root.isAirpodsDevice(device))
                    hasAirpodsConnected = true;

                if (root.connectedBattery < 0)
                    root.connectedBattery = root.deviceBatteryValue(device);
            }
        }

        if (hasAirpodsConnected && root.connectedBattery <= 0 && root.librepodsBattery > 0) {
            root.connectedBattery = root.librepodsBattery;
            root.logDebug("using librepods battery fallback=" + root.librepodsBattery);
        }

        root.connectedNames = names.join(", ");

        if (root.pendingDeviceKey.length > 0) {
            const pendingStillExists = list.some(device => root.deviceKey(device) === root.pendingDeviceKey);
            if (!pendingStillExists)
                root.pendingDeviceKey = "";
        }

        root.requestScanState();
        root.requestLibrepodsBattery();
    }

    function requestLibrepodsBattery() {
        if (librepodsTooltipProcess.running)
            return;
        librepodsTooltipProcess.running = true;
    }

    function toggleAdapterEnabled() {
        if (!root.adapter)
            return;
        root.adapter.enabled = !root.adapter.enabled;
        if (!root.adapter.enabled) {
            root.moduleScanSession = false;
            root.desiredScanState = false;
            root.scanActive = false;
            root.refreshBluetooth();
        }
    }

    function setDiscovery(active) {
        if (!root.adapter || !root.adapterEnabled)
            return;

        root.logDebug("setDiscovery(" + active + ") requested; adapterDiscovering=" + root.adapterDiscovering + " scanActive=" + root.scanActive + " desiredScanState=" + root.desiredScanState);
        root.lastScanAction = active ? "start" : "stop";
        root.desiredScanState = active;
        root.moduleScanSession = active;
        root.scanEnsureAttempts = 0;

        // Short-circuit only if both observed states already match the request.
        if (root.adapterDiscovering === active && root.scanActive === active) {
            root.scanActive = active;
            root.logDebug("setDiscovery early-return (already in requested state)");
            scanEnsureTimer.stop();
            return;
        }

        root.scanActive = active;
        root.lastScanSource = "module";
        root.adapter.discovering = active;
        root.logDebug("adapter.discovering set to " + active + "; now adapterDiscovering=" + root.adapterDiscovering);

        root.dispatchScanCli(active, "setDiscovery");

        refreshTimer.restart();
        scanRefreshTimer.restart();
        scanEnsureTimer.start();
    }

    function toggleDiscovery() {
        const currentlyScanning = root.moduleScanSession || root.desiredScanState;
        root.logDebug("toggleDiscovery currentlyScanning=" + currentlyScanning
            + " (moduleScanSession=" + root.moduleScanSession
            + ", desired=" + root.desiredScanState
            + ", scanActive=" + root.scanActive
            + ", adapterDiscovering=" + root.adapterDiscovering + ")");
        root.setDiscovery(!currentlyScanning);
    }

    function dispatchScanCli(active, source) {
        const desired = active ? "on" : "off";
        const adapterId = root.adapter && root.adapter.adapterId ? String(root.adapter.adapterId) : "";
        const script = adapterId.length > 0
            ? ("{ echo 'select " + adapterId + "'; echo 'scan " + desired + "'; echo 'quit'; } | bluetoothctl >/dev/null 2>&1")
            : ("{ echo 'scan " + desired + "'; echo 'quit'; } | bluetoothctl >/dev/null 2>&1");

        root.lastScanSource = source;
        root.logDebug("scan cli dispatch source=" + source + " command=" + script);
        Common.ProcessHelper.execDetached(["sh", "-lc", script]);
    }

    function parseDiscoveryOwnerLine(line) {
        const text = String(line || "").trim();
        if (text.length === 0)
            return;
        if (text.indexOf("member=StartDiscovery") < 0)
            return;

        const senderMatch = text.match(/sender=([^ ]+)/);
        if (!senderMatch || senderMatch.length < 2)
            return;

        const sender = String(senderMatch[1]).trim();
        if (sender.length === 0 || sender === root.lastStartDiscoverySender)
            return;

        root.lastStartDiscoverySender = sender;
        root.lastStartDiscoveryPid = -1;
        root.lastStartDiscoveryProcess = "";
        root.logDebug("StartDiscovery caller seen sender=" + sender + "; resolving pid");
        resolveDiscoveryPidRunner.trigger();
    }

    function logDiscoveryOwner(context) {
        if (root.lastStartDiscoverySender.length === 0) {
            root.logDebug(context + " discovery owner unknown (no StartDiscovery sender seen)");
            probeScanHoldersRunner.trigger();
            return;
        }
        root.logDebug(context + " possible holder sender=" + root.lastStartDiscoverySender
            + " pid=" + root.lastStartDiscoveryPid
            + " process=" + root.lastStartDiscoveryProcess);
        probeScanHoldersRunner.trigger();
    }

    function notifyScanStopFailure() {
        const nowMs = Date.now();
        if (nowMs - root.lastScanStopNotifyMs < 15000)
            return;
        root.lastScanStopNotifyMs = nowMs;

        let detail = "Discovery appears to be owned by another process.";
        if (root.lastScanHolders.length > 0) {
            const firstLine = root.lastScanHolders.split("\n")[0].trim();
            if (firstLine.length > 0)
                detail = "Possible holder: " + firstLine;
        }

        Common.ProcessHelper.execDetached(["notify-send",
            "Bluetooth scan stop failed",
            detail
        ]);
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
            root.moduleScanSession = false;
            root.desiredScanState = false;
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
                if (root.scanActive && !root.moduleScanSession && !root.desiredScanState)
                    root.logDebug("scan appears to be held by another client/session");
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const err = String(this.text || "").trim();
                if (err.length > 0)
                    root.logDebug("scan probe stderr: " + err);
            }
        }

        // qmllint disable signal-handler-parameters
        onExited: code => root.logDebug("scan probe exited code=" + code)
        // qmllint enable signal-handler-parameters
    }

    ProcessMonitor {
        id: discoveryOwnerMonitor
        enabled: root.adapterEnabled
        processName: "BlueZStartDiscoveryMonitor"
        command: ["dbus-monitor", "--system", "type='method_call',destination='org.bluez',interface='org.bluez.Adapter1',member='StartDiscovery'"]
        onOutput: data => root.parseDiscoveryOwnerLine(data)
    }

    CommandRunner {
        id: resolveDiscoveryPidRunner
        intervalMs: 0
        timeoutMs: 3000
        command: root.lastStartDiscoverySender.length > 0
            ? ["busctl", "--system", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", root.lastStartDiscoverySender]
            : []
        onRan: function(output) {
            const m = String(output || "").match(/\bu\s+([0-9]+)/);
            if (!m) {
                root.logDebug("discovery pid parse failed sender=" + root.lastStartDiscoverySender + " output=" + output);
                return;
            }
            const pid = parseInt(m[1], 10);
            if (!Number.isFinite(pid))
                return;

            root.lastStartDiscoveryPid = pid;
            resolveDiscoveryProcessRunner.trigger();
        }
    }

    CommandRunner {
        id: resolveDiscoveryProcessRunner
        intervalMs: 0
        timeoutMs: 3000
        command: root.lastStartDiscoveryPid > 0
            ? ["sh", "-lc", "ps -p " + root.lastStartDiscoveryPid + " -o comm= 2>/dev/null | head -n1"]
            : []
        onRan: function(output) {
            root.lastStartDiscoveryProcess = String(output || "").trim();
            root.logDebug("resolved StartDiscovery caller sender=" + root.lastStartDiscoverySender
                + " pid=" + root.lastStartDiscoveryPid
                + " process=" + root.lastStartDiscoveryProcess);
        }
    }

    CommandRunner {
        id: probeScanHoldersRunner
        intervalMs: 0
        timeoutMs: 3000
        command: ["sh", "-lc", "ps -eo pid,user,cmd | grep -E '(btmgmt|bluetoothctl|blueman|blueberry|kdeconnectd|librepods)' | grep -v grep | head -n 20"]
        onRan: function(output) {
            root.lastScanHolders = String(output || "").trim();
            if (root.lastScanHolders.length > 0)
                root.logDebug("possible scan holders:\n" + root.lastScanHolders);
            else
                root.logDebug("possible scan holders: none matched");
        }
    }

    Process {
        id: librepodsTooltipProcess
        command: ["sh", "-lc", "svc=$(busctl --user list 2>/dev/null | awk '$1 ~ /^org\\.kde\\.StatusNotifierItem-/ {print $1}' | while read -r s; do id=$(busctl --user get-property \"$s\" /StatusNotifierItem org.kde.StatusNotifierItem Id 2>/dev/null); echo \"$id\" | grep -qi '\"librepods\"' && { echo \"$s\"; break; }; done); [ -n \"$svc\" ] && busctl --user get-property \"$svc\" /StatusNotifierItem org.kde.StatusNotifierItem ToolTip 2>/dev/null || true"]

        stdout: StdioCollector {
            onStreamFinished: {
                const parsed = root.parseLibrepodsTooltipParts(this.text);
                if (parsed.average > 0) {
                    const changed = parsed.average !== root.librepodsBattery
                        || parsed.left !== root.librepodsBatteryLeft
                        || parsed.right !== root.librepodsBatteryRight
                        || parsed.caseBattery !== root.librepodsBatteryCase;

                    root.librepodsBattery = parsed.average;
                    root.librepodsBatteryLeft = parsed.left;
                    root.librepodsBatteryRight = parsed.right;
                    root.librepodsBatteryCase = parsed.caseBattery;

                    root.logDebug("librepods tooltip battery parsed avg=" + parsed.average
                        + " L=" + parsed.left + " R=" + parsed.right + " C=" + parsed.caseBattery);
                    if (changed && root.connectedBattery <= 0 && root.connectedCount > 0)
                        root.refreshBluetooth();
                } else {
                    root.librepodsBattery = -1;
                    root.librepodsBatteryLeft = -1;
                    root.librepodsBatteryRight = -1;
                    root.librepodsBatteryCase = -1;
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const err = String(this.text || "").trim();
                if (err.length > 0)
                    root.logDebug("librepods probe stderr: " + err);
            }
        }
    }

    Timer {
        id: scanPollTimer
        interval: 2000
        repeat: true
        running: root.tooltipActive && root.adapterEnabled
        onTriggered: {
            root.requestScanState();
            root.requestLibrepodsBattery();
        }
    }

    Timer {
        id: scanRefreshTimer
        interval: 500
        repeat: false
        onTriggered: root.requestScanState()
    }

    Timer {
        id: scanEnsureTimer
        interval: 1200
        repeat: true
        running: false
        onTriggered: {
            const adapterState = root.adapterDiscovering;
            const uiState = root.scanActive;
            const desired = root.desiredScanState;
            const matches = (adapterState === desired && uiState === desired);

            root.logDebug("scanEnsure attempt=" + root.scanEnsureAttempts
                + " desired=" + desired
                + " adapterDiscovering=" + adapterState
                + " scanActive=" + uiState);

            if (matches || root.scanEnsureAttempts >= 3) {
                running = false;
                root.requestScanState();
                if (!matches && !desired) {
                    root.logDiscoveryOwner("scanEnsure exhausted;");
                    root.notifyScanStopFailure();
                }
                return;
            }

            root.scanEnsureAttempts += 1;
            if (root.adapter && root.adapterEnabled)
                root.adapter.discovering = desired;
            if (!desired)
                root.logDiscoveryOwner("scanEnsure retry;");
            root.dispatchScanCli(desired, "ensureTimer");
            root.requestScanState();
        }
    }

    IpcHandler {
        id: scanIpc
        target: "bluetooth-scan"

        function start() {
            root.lastScanSource = "ipc.start";
            root.setDiscovery(true);
        }

        function stop() {
            root.lastScanSource = "ipc.stop";
            root.setDiscovery(false);
        }

        function toggle() {
            root.lastScanSource = "ipc.toggle";
            root.toggleDiscovery();
        }

        function status() {
            return JSON.stringify({
                adapterEnabled: root.adapterEnabled,
                adapterId: root.adapter && root.adapter.adapterId ? String(root.adapter.adapterId) : "",
                adapterDiscovering: root.adapterDiscovering,
                scanActive: root.scanActive,
                moduleScanSession: root.moduleScanSession,
                desiredScanState: root.desiredScanState,
                scanEnsureAttempts: root.scanEnsureAttempts,
                lastScanSource: root.lastScanSource,
                lastScanAction: root.lastScanAction,
                lastStartDiscoverySender: root.lastStartDiscoverySender,
                lastStartDiscoveryPid: root.lastStartDiscoveryPid,
                lastStartDiscoveryProcess: root.lastStartDiscoveryProcess,
                lastScanHolders: root.lastScanHolders
            });
        }
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
            readonly property var pairedDevices: root.deviceSnapshot.filter(device => !!(device && device.paired))
            readonly property var unpairedDevices: root.deviceSnapshot.filter(device => !!(device && !device.paired))
            readonly property int pairedRowsShown: Math.min(maxVisibleRows, pairedDevices.length)
            readonly property int pairedRowsHeight: pairedRowsShown > 0
                ? (pairedRowsShown * rowHeight) + ((pairedRowsShown - 1) * Config.space.xs)
                : 0
            readonly property int unpairedRowsShown: Math.min(maxVisibleRows, unpairedDevices.length)
            readonly property int unpairedRowsHeight: unpairedRowsShown > 0
                ? (unpairedRowsShown * rowHeight) + ((unpairedRowsShown - 1) * Config.space.xs)
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
                            text: root.connectedBattery > 0
                                ? (root.statusLabel() + " • "
                                    + (root.librepodsBatterySummary().length > 0
                                        ? root.librepodsBatterySummary()
                                        : (root.connectedBattery.toString() + "%")))
                                : root.statusLabel()
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
                visible: root.connectedBattery > 0
            }

            StackLayout {
                Layout.fillWidth: true
                currentIndex: root.detailsExpanded ? 1 : 0

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Config.space.xs
                    visible: root.deviceSnapshot.length > 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: Config.space.xs
                        spacing: Config.space.sm

                        Text {
                            color: Config.color.primary
                            font.family: Config.fontFamily
                            font.letterSpacing: 1.5
                            font.pixelSize: Config.type.labelSmall.size
                            font.weight: Font.Black
                            text: "DEVICES"
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            color: Qt.alpha(Config.color.outline_variant, 0.55)
                            implicitHeight: 1
                            radius: 1
                        }

                        Item {
                            Layout.fillHeight: true
                            Layout.preferredWidth: toggleRow.implicitWidth + (Config.space.xs * 2)
                            visible: menu.unpairedDevices.length > 0

                            RowLayout {
                                id: toggleRow
                                anchors.centerIn: parent
                                spacing: Config.space.xs

                                Text {
                                    color: Config.color.on_surface_variant
                                    font.family: Config.fontFamily
                                    font.pixelSize: Config.type.labelSmall.size
                                    text: menu.unpairedDevices.length.toString()
                                }

                                Text {
                                    color: Config.color.on_surface_variant
                                    font.family: Config.iconFontFamily
                                    font.pixelSize: Config.type.labelLarge.size
                                    text: root.showUnpairedDevices ? "󰅀" : "󰅂"
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showUnpairedDevices = !root.showUnpairedDevices
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: menu.pairedRowsHeight
                        clip: true
                        visible: menu.pairedRowsShown > 0

                        ListView {
                            anchors.fill: parent
                            boundsBehavior: Flickable.StopAtBounds
                            boundsMovement: Flickable.StopAtBounds
                            clip: true
                            flickableDirection: Flickable.VerticalFlick
                            interactive: menu.pairedDevices.length > menu.maxVisibleRows
                            model: menu.pairedDevices
                            spacing: Config.space.xs
                            delegate: BluetoothDeviceRow {
                                moduleRoot: root
                                rowHeight: menu.rowHeight
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: menu.unpairedRowsHeight
                        clip: true
                        visible: root.showUnpairedDevices && menu.unpairedRowsShown > 0

                        ListView {
                            anchors.fill: parent
                            boundsBehavior: Flickable.StopAtBounds
                            boundsMovement: Flickable.StopAtBounds
                            clip: true
                            flickableDirection: Flickable.VerticalFlick
                            interactive: menu.unpairedDevices.length > menu.maxVisibleRows
                            model: menu.unpairedDevices
                            spacing: Config.space.xs
                            delegate: BluetoothDeviceRow {
                                moduleRoot: root
                                rowHeight: menu.rowHeight
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
                        label: "Battery (L/R/C)"
                        value: root.librepodsBatterySummary()
                        visible: root.librepodsBatterySummary().length > 0
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
                    text: (root.moduleScanSession || root.desiredScanState) ? "Stop Scan" : "Scan"
                    onClicked: scanIpc.toggle()
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
