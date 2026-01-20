/**
 * @module BacklightModule
 * @description Screen brightness control module with hardware monitoring and interactive controls
 *
 * Features:
 * - Real-time brightness monitoring via sysfs (/sys/class/backlight)
 * - Hardware event detection via udevadm monitor (150ms debounced when tooltip closed)
 * - Interactive slider control (1-100%)
 * - Quick preset buttons (20%, 50%, 80%, 100%)
 * - Mouse wheel adjustment support
 * - Automatic crash recovery for udev monitor (exponential backoff)
 *
 * Dependencies:
 * - brillo: Command-line brightness control utility
 * - udevadm: Hardware event monitoring (optional but recommended)
 * - /sys/class/backlight/<device>/: Sysfs brightness interface
 *
 * Configuration:
 * - backlightDevice: Device name (default: "intel_backlight")
 * - brightnessDebounceMs: Event debounce interval (default: 150ms)
 * - onScrollUpCommand: Command for scroll up (default: "brillo -U 1")
 * - onScrollDownCommand: Command for scroll down (default: "brillo -A 1")
 *
 * Performance:
 * - Selective event filtering: only reacts to ACTION=change events (not property lines)
 * - Debounced event handling reduces CPU load during rapid brightness changes
 * - Debounce bypassed when tooltip is open for immediate visual feedback
 * - Single brightness change: 1 trigger per change (was ~24 events with broad filter)
 * - File reads: 2 per brightness change (actual + max brightness)
 *
 * Error Handling:
 * - Command availability checks on startup
 * - Graceful degradation when tools unavailable
 * - Auto-restart for crashed udev monitor (exponential backoff up to 30s)
 * - Console warnings for missing dependencies
 *
 * @example
 * // Basic usage with defaults
 * BacklightModule {}
 *
 * @example
 * // Custom device and debounce interval
 * BacklightModule {
 *     backlightDevice: "amdgpu_bl0"
 *     brightnessDebounceMs: 200
 * }
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../components"

ModuleContainer {
    id: root

    readonly property string actualBrightnessPath: root.backlightDevice !== "" ? "/sys/class/backlight/" + root.backlightDevice + "/actual_brightness" : ""
    property string backlightDevice: "intel_backlight"
    property int brightnessPercent: -1
    readonly property string iconText: root.iconForBrightness()
    property var icons: ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "󰃚"]
    readonly property string maxBrightnessPath: root.backlightDevice !== "" ? "/sys/class/backlight/" + root.backlightDevice + "/max_brightness" : ""
    property string onScrollDownCommand: "brillo -A 1"
    property string onScrollUpCommand: "brillo -U 1"
    property int sliderValue: 0
    property int udevRestartAttempts: 0
    property bool udevDegraded: false
    property bool brilloAvailable: false
    property bool udevadmAvailable: false
    property int brightnessDebounceMs: 150

    function handleUdevEvent(data) {
        const line = (data || "").trim();
        if (!line)
            return;

        // Only trigger on actual change events, not every property line
        // udevadm monitor --property outputs: ACTION=change when brightness changes
        // The --subsystem-match=backlight filter ensures we only get backlight events
        if (line === "ACTION=change") {
            root.scheduleBrightnessRefresh();
        }
    }
    function scheduleBrightnessRefresh() {
        // Skip debounce when tooltip is open for immediate feedback
        if (root.tooltipActive) {
            root.refreshBrightness();
            return;
        }
        if (!brightnessDebounceTimer.running)
            brightnessDebounceTimer.start();
    }
    function iconForBrightness() {
        const percent = root.brightnessPercent;
        if (percent < 0)
            return root.icons[root.icons.length - 1];
        const step = 100 / root.icons.length;
        const index = Math.min(root.icons.length - 1, Math.floor(percent / step));
        return root.icons[index];
    }
    function refreshBrightness() {
        if (root.actualBrightnessPath === "")
            return;
        actualBrightnessFile.reload();
        maxBrightnessFile.reload();
    }
    function setBrightness(percent) {
        if (!root.brilloAvailable)
            return;
        const next = Math.max(1, Math.min(100, percent));
        Quickshell.execDetached(["sh", "-c", "brillo -S " + next]);
    }
    function updateBrightnessFromFiles() {
        if (root.actualBrightnessPath === "" || root.maxBrightnessPath === "") {
            root.brightnessPercent = -1;
            root.sliderValue = 0;
            return;
        }
        const currentText = actualBrightnessFile.text().trim();
        const maxText = maxBrightnessFile.text().trim();
        const currentValue = parseInt(currentText, 10);
        const maxValue = parseInt(maxText, 10);
        if (!isFinite(currentValue) || !isFinite(maxValue) || maxValue <= 0) {
            root.brightnessPercent = -1;
            root.sliderValue = 0;
            return;
        }
        root.brightnessPercent = Math.round((currentValue / maxValue) * 100);
        root.sliderValue = root.brightnessPercent;
    }

    tooltipHoverable: true
    tooltipText: ""
    tooltipTitle: "Brightness"

    content: [
        IconLabel {
            color: Config.m3.warning
            text: root.iconText
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
                        color: Config.m3.warning
                        font.pixelSize: Config.type.headlineLarge.size
                        text: root.iconText
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
                        text: "Brightness"
                    }
                    Text {
                        color: Config.m3.onSurfaceVariant
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.labelMedium.size
                        text: root.brightnessPercent >= 0 ? root.brightnessPercent + "%" : "Unavailable"
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
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
                    text: "BRIGHTNESS DETAILS"
                }
                LevelSlider {
                    Layout.fillWidth: true
                    enabled: root.brightnessPercent >= 0
                    fillColor: Config.m3.warning
                    maximum: 100
                    minimum: 1
                    value: root.sliderValue

                    onUserChanged: value => {
                        root.sliderValue = Math.round(value);
                        root.setBrightness(root.sliderValue);
                    }
                }
                InfoRow {
                    Layout.fillWidth: true
                    label: "Device"
                    value: root.backlightDevice
                    visible: root.backlightDevice !== ""
                }
            }
            TooltipActionsRow {
                spacing: Config.space.sm

                ActionChip {
                    Layout.fillWidth: true
                    text: "20%"

                    onClicked: root.setBrightness(20)
                }
                ActionChip {
                    Layout.fillWidth: true
                    text: "50%"

                    onClicked: root.setBrightness(50)
                }
                ActionChip {
                    Layout.fillWidth: true
                    text: "80%"

                    onClicked: root.setBrightness(80)
                }
                ActionChip {
                    Layout.fillWidth: true
                    text: "100%"

                    onClicked: root.setBrightness(100)
                }
            }
        }
    }

    Component.onCompleted: {
        DependencyCheck.require("brillo", "BacklightModule", function (available) {
            root.brilloAvailable = available;
        });
        DependencyCheck.require("udevadm", "BacklightModule", function (available) {
            root.udevadmAvailable = available;
        });
        root.refreshBrightness();
    }
    onBacklightDeviceChanged: root.refreshBrightness()
    FileView {
        id: actualBrightnessFile

        blockLoading: true
        path: root.actualBrightnessPath

        onTextChanged: root.updateBrightnessFromFiles()
    }
    FileView {
        id: maxBrightnessFile

        blockLoading: true
        path: root.maxBrightnessPath

        onTextChanged: root.updateBrightnessFromFiles()
    }
    Timer {
        id: brightnessDebounceTimer

        interval: root.brightnessDebounceMs
        repeat: false

        onTriggered: root.refreshBrightness()
    }
    Timer {
        id: udevRestartTimer

        interval: Math.min(30000, 1000 * Math.pow(2, root.udevRestartAttempts))
        running: false

        onTriggered: {
            root.udevDegraded = false;
            udevMonitor.running = root.udevadmAvailable && root.backlightDevice !== "";
        }
    }
    Timer {
        id: udevBackoffResetTimer

        interval: 60000
        running: udevMonitor.running
        repeat: false

        onTriggered: {
            if (root.udevRestartAttempts > 0) {
                console.log("BacklightModule: udevadm monitor stable for 60s, resetting backoff");
            }
            root.udevRestartAttempts = 0;
        }
    }
    Process {
        id: udevMonitor

        command: ["udevadm", "monitor", "--subsystem-match=backlight", "--property"]
        running: root.udevadmAvailable && root.backlightDevice !== ""

        stdout: SplitParser {
            onRead: function (data) {
                root.handleUdevEvent(data);
            }
        }
        // qmllint disable signal-handler-parameters
        onExited: code => {
            if (root.udevRestartAttempts === 0) {
                console.warn(`BacklightModule: udevadm monitor exited with code ${code}, attempting restart`);
            } else {
                const backoff = Math.min(30000, 1000 * Math.pow(2, root.udevRestartAttempts));
                console.warn(`BacklightModule: udevadm monitor crashed again (attempt ${root.udevRestartAttempts + 1}), next restart in ${backoff}ms`);
            }
            root.udevDegraded = true;
            root.udevRestartAttempts++;
            udevBackoffResetTimer.stop();
            udevRestartTimer.restart();
        }
        // qmllint enable signal-handler-parameters
    }
    MouseArea {
        anchors.fill: parent

        onWheel: function (wheel) {
            if (!root.brilloAvailable)
                return;
            if (wheel.angleDelta.y > 0)
                Quickshell.execDetached(["sh", "-c", root.onScrollUpCommand]);
            else if (wheel.angleDelta.y < 0)
                Quickshell.execDetached(["sh", "-c", root.onScrollDownCommand]);
        }
    }
}
