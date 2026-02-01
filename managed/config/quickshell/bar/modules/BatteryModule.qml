/**
 * @module BatteryModule
 * @description Battery status module with UPower integration
 *
 * Features:
 * - Battery percentage and charging state display
 * - Time remaining estimates (charging/discharging)
 * - Battery health percentage tracking
 * - Power profile quick switcher (PowerSaver/Balanced/Performance)
 * - Click toggles time/percentage display
 *
 * Dependencies:
 * - Quickshell.Services.UPower: Battery state and power profiles
 */
pragma ComponentBehavior: Bound
import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

ModuleContainer {
    id: root

    property int healthPercent: -1
    property bool showTime: false

    function normalizePercent(value) {
        if (!isFinite(value))
            return 0;
        return value <= 1 ? value * 100 : value;
    }

    function batteryColor(device) {
        if (!device || !device.ready)
            return Config.color.on_surface;

        if (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge)
            return Config.color.tertiary;

        if (device.state === UPowerDeviceState.Discharging || device.state === UPowerDeviceState.PendingDischarge)
            return Config.color.error;

        return Config.color.on_surface;
    }
    function batteryIcon(device) {
        if (!device || !device.ready)
            return "";

        if (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge)
            return "󰂄";

        const percent = root.normalizePercent(device.percentage);
        if (percent <= 10)
            return "󰁺";

        if (percent <= 20)
            return "󰁻";

        if (percent <= 30)
            return "󰁼";

        if (percent <= 40)
            return "󰁽";

        if (percent <= 50)
            return "󰁾";

        if (percent <= 60)
            return "󰁿";

        if (percent <= 70)
            return "󰂀";

        if (percent <= 80)
            return "󰂁";

        if (percent <= 90)
            return "󰂂";

        return "󰁹";
    }
    function batteryPercentValue(device) {
        if (!device || !device.ready)
            return 0;

        const percent = root.normalizePercent(device.percentage);
        return Math.max(0, Math.min(100, percent));
    }
    function formatSeconds(seconds) {
        if (!seconds || seconds <= 0)
            return "";

        const totalMinutes = Math.floor(seconds / 60);
        const hours = Math.floor(totalMinutes / 60);
        const minutes = totalMinutes % 60;
        if (hours <= 0)
            return minutes + "m";

        if (minutes <= 0)
            return hours + "h";

        return hours + "h " + minutes + "m";
    }
    function healthFromDevice(device) {
        if (!device)
            return -1;

        if (!device.ready)
            return -1;

        const healthRaw = device.healthPercentage;
        const health = root.normalizePercent(healthRaw);
        if (isFinite(health) && health > 0)
            return Math.round(health);

        // Fallback: if we at least have a full-capacity reading, assume design==full (100%).
        const full = device.energyCapacity;
        if (isFinite(full) && full > 0)
            return 100;

        // As a last resort, derive full from energy + percentage and assume design==full.
        const percent = root.normalizePercent(device.percentage);
        const percentFrac = percent / 100;
        if (isFinite(device.energy) && isFinite(percentFrac) && percentFrac > 0)
            return 100;

        return -1;
    }
    function healthLabel() {
        return root.healthPercent >= 0 ? root.healthPercent + "%" : "—";
    }
    function percentLabel(device) {
        if (!device || !device.ready)
            return "";

        const percent = root.normalizePercent(device.percentage);
        return Math.round(percent) + "%";
    }
    function refreshHealth() {
        const fromDevice = root.healthFromDevice(UPower.displayDevice);
        if (fromDevice >= 0)
            root.healthPercent = fromDevice;
    }
    function stateLabel(device) {
        if (!device || !device.ready)
            return "Unknown";

        const timeRemaining = root.timeRemainingLabel(device);
        switch (device.state) {
        case UPowerDeviceState.Charging:
        case UPowerDeviceState.PendingCharge:
            return "Charging" + (timeRemaining ? (" · " + timeRemaining) : "");
        case UPowerDeviceState.Discharging:
        case UPowerDeviceState.PendingDischarge:
            return "Discharging" + (timeRemaining ? (" · " + timeRemaining) : "");
        case UPowerDeviceState.FullyCharged:
            return "Full";
        default:
            return "Idle";
        }
    }
    function timeLabel(device) {
        if (!device || !device.ready)
            return "";

        const time = device.timeToEmpty > 0 ? device.timeToEmpty : device.timeToFull;
        const formatted = formatSeconds(time);
        return formatted ? formatted : "";
    }
    function timeRemainingLabel(device) {
        if (!device || !device.ready)
            return "";

        const isCharging = device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge;
        const isDischarging = device.state === UPowerDeviceState.Discharging || device.state === UPowerDeviceState.PendingDischarge;
        let seconds = 0;
        if (isCharging)
            seconds = device.timeToFull;
        else if (isDischarging)
            seconds = device.timeToEmpty;
        const formatted = root.formatSeconds(seconds);
        return formatted ? formatted + " left" : "";
    }
    function tooltipLabel() {
        const device = UPower.displayDevice;
        if (!device || !device.ready)
            return "Battery: unknown";

        const percentText = root.percentLabel(device);
        const timeText = root.timeLabel(device);
        const timeSuffix = timeText ? " (" + timeText + ")" : "";
        return "Battery: " + percentText + timeSuffix;
    }

    tooltipHoverable: true
    tooltipText: root.tooltipLabel()
    tooltipTitle: "Battery"

    content: [
        IconTextRow {
            iconColor: root.batteryColor(UPower.displayDevice)
            iconText: root.batteryIcon(UPower.displayDevice)
            spacing: root.contentSpacing
            text: root.showTime ? root.timeLabel(UPower.displayDevice) : root.percentLabel(UPower.displayDevice)
            textColor: root.batteryColor(UPower.displayDevice)
        }
    ]
    tooltipContent: Component {
        ColumnLayout {
            spacing: Config.space.md
            width: 240 // Match CalendarTooltip width

            // Header Section
            TooltipHeader {
                icon: root.batteryIcon(UPower.displayDevice)
                iconColor: root.batteryColor(UPower.displayDevice)
                subtitle: root.stateLabel(UPower.displayDevice)
                title: root.percentLabel(UPower.displayDevice)
            }
            ProgressBar {
                Layout.fillWidth: true
                fillColor: root.batteryColor(UPower.displayDevice)
                Layout.preferredHeight: Config.space.xs
                implicitHeight: Config.space.xs
                trackColor: Config.color.surface_variant
                value: root.batteryPercentValue(UPower.displayDevice) / 100
            }

            // Power Mode Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.xs

                SectionHeader {
                    text: "POWER PROFILE"
                }
                TooltipActionsRow {
                    spacing: Config.space.sm

                    ActionChip {
                        Layout.fillWidth: true
                        active: PowerProfiles.profile === PowerProfile.PowerSaver
                        text: "󰾆"

                        onClicked: PowerProfiles.profile = PowerProfile.PowerSaver
                    }
                    ActionChip {
                        Layout.fillWidth: true
                        active: PowerProfiles.profile === PowerProfile.Balanced
                        text: "󰾅"

                        onClicked: PowerProfiles.profile = PowerProfile.Balanced
                    }
                    ActionChip {
                        Layout.fillWidth: true
                        active: PowerProfiles.profile === PowerProfile.Performance
                        text: ""

                        onClicked: PowerProfiles.profile = PowerProfile.Performance
                    }
                }
            }

            // Health Section
            InfoRow {
                Layout.fillWidth: true
                icon: "󰁹"
                label: "Battery Health"
                opacity: 0.6
                showLeader: false
                value: root.healthLabel()
            }
        }
    }

    Component.onCompleted: root.refreshHealth()
    onTooltipActiveChanged: {
        if (root.tooltipActive)
            root.refreshHealth();
    }

    Connections {
        function onEnergyCapacityChanged() {
            root.refreshHealth();
        }
        function onHealthPercentageChanged() {
            root.refreshHealth();
        }
        function onPercentageChanged() {
            root.refreshHealth();
        }
        function onReadyChanged() {
            root.refreshHealth();
        }

        ignoreUnknownSignals: true
        target: UPower.displayDevice
    }

    onClicked: root.showTime = !root.showTime
}
