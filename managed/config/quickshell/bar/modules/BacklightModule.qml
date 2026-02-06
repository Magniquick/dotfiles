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
import ".."
import "../components"

ModuleContainer {
    id: root

    readonly property string backlightDevice: BacklightService.backlightDevice
    readonly property int brightnessPercent: BacklightService.brightnessPercent
    readonly property string iconText: root.iconForBrightness()
    property var icons: ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "󰃚"]
    readonly property int sliderValue: BacklightService.sliderValue
    readonly property bool brilloAvailable: BacklightService.brilloAvailable
    function iconForBrightness() {
        const percent = root.brightnessPercent;
        if (percent < 0)
            return root.icons[root.icons.length - 1];
        const step = 100 / root.icons.length;
        const index = Math.min(root.icons.length - 1, Math.floor(percent / step));
        return root.icons[index];
    }
    function setBrightness(percent) {
        BacklightService.setBrightness(percent);
    }

    tooltipHoverable: true
    tooltipText: ""
    tooltipTitle: "Brightness"

    content: [
        IconLabel {
            color: Config.color.secondary
            text: root.iconText
        }
    ]
    tooltipContent: Component {
        ColumnLayout {
            spacing: Config.space.md
            width: 240

            // Header Section
            TooltipHeader {
                icon: root.iconText
                iconColor: Config.color.secondary
                subtitle: root.brightnessPercent >= 0 ? root.brightnessPercent + "%" : "Unavailable"
                title: "Brightness"
            }

            // Details Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.xs

                SectionHeader {
                    text: "BRIGHTNESS DETAILS"
                }
                LevelSlider {
                    Layout.fillWidth: true
                    enabled: root.brightnessPercent >= 0
                    fillColor: Config.color.secondary
                    maximum: 100
                    minimum: 1
                    value: root.sliderValue

                    onUserChanged: value => {
                        root.setBrightness(Math.round(value));
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

    MouseArea {
        anchors.fill: parent

        onWheel: function (wheel) {
            if (wheel.angleDelta.y > 0)
                BacklightService.scrollUp();
            else if (wheel.angleDelta.y < 0)
                BacklightService.scrollDown();
        }
    }
}
