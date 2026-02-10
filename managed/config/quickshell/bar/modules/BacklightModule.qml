/**
 * @module BacklightModule
 * @description Screen brightness control module (internal backlight + optional external DDC)
 *
 * Features:
 * - Per-screen control (each bar instance controls its own `screen`)
 * - Internal backlight via `qsnative.BacklightProvider` (sysfs + udev, no polling)
 * - External monitors via DDC/CI using `ddcutil` (if installed and detected)
 * - Interactive slider control (1-100%)
 * - Quick preset buttons (20%, 50%, 80%, 100%)
 * - Mouse wheel adjustment support
 *
 * Dependencies:
 * - Internal: `qsnative` module (BacklightProvider) + permission to write `/sys/class/backlight/<device>/brightness`
 * - External (optional): `ddcutil`
 *
 * Configuration:
 * - None (device detection is automatic)
 *
 * @example
 * // Basic usage with defaults
 * BacklightModule { screen: someShellScreen }
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"

ModuleContainer {
    id: root

    required property var screen

    readonly property var brightnessMonitor: BrightnessService.getMonitorForScreen(root.screen)
    readonly property string backlightDevice: root.brightnessMonitor && root.brightnessMonitor.method === "backlight" ? root.brightnessMonitor.backlightDevice : ""
    readonly property string method: root.brightnessMonitor ? root.brightnessMonitor.method : "none"
    readonly property string ddcBusNum: root.brightnessMonitor && root.brightnessMonitor.method === "ddc" ? root.brightnessMonitor.ddcBusNum : ""

    readonly property int brightnessPercent: {
        if (!root.brightnessMonitor || !isFinite(root.brightnessMonitor.brightness))
            return -1;
        return Math.round(root.brightnessMonitor.brightness * 100);
    }
    readonly property string iconText: root.iconForBrightness()
    property var icons: ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "󰃚"]
    readonly property int sliderValue: root.brightnessPercent >= 0 ? root.brightnessPercent : 0
    function iconForBrightness() {
        const percent = root.brightnessPercent;
        if (percent < 0)
            return root.icons[root.icons.length - 1];
        const step = 100 / root.icons.length;
        const index = Math.min(root.icons.length - 1, Math.floor(percent / step));
        return root.icons[index];
    }
    function setBrightness(percent) {
        if (!root.brightnessMonitor)
            return;
        const next = Math.max(1, Math.min(100, percent));
        root.brightnessMonitor.setBrightness(next / 100.0);
    }

    tooltipHoverable: true
    tooltipText: ""
    tooltipTitle: "Brightness"

    onTooltipActiveChanged: {
        if (root.tooltipActive && root.brightnessMonitor && typeof root.brightnessMonitor.refresh === "function") {
            root.brightnessMonitor.refresh();
        }
    }

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
                    value: root.method === "ddc" ? (root.screen ? root.screen.name : "") : root.backlightDevice
                    visible: root.method !== "none"
                }
                InfoRow {
                    Layout.fillWidth: true
                    label: "Method"
                    value: root.method
                    visible: root.method !== "none"
                }
                InfoRow {
                    Layout.fillWidth: true
                    label: "DDC Bus"
                    value: root.ddcBusNum
                    visible: root.method === "ddc" && root.ddcBusNum !== ""
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
            if (!root.brightnessMonitor)
                return;
            const step = 1;
            if (wheel.angleDelta.y > 0)
                root.setBrightness(root.brightnessPercent + step);
            else if (wheel.angleDelta.y < 0)
                root.setBrightness(root.brightnessPercent - step);
        }
    }
}
