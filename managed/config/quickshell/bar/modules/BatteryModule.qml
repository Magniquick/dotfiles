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
import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower

ModuleContainer {
    id: root

    property int healthPercent: -1
    property bool showTime: false

    function batteryColor(device) {
        if (!device || !device.ready)
            return Config.m3.onSurface;

        if (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge)
            return Config.m3.success;

        if (device.state === UPowerDeviceState.Discharging || device.state === UPowerDeviceState.PendingDischarge)
            return Config.m3.error;

        return Config.m3.onSurface;
    }
    function batteryIcon(device) {
        if (!device || !device.ready)
            return "";

        if (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge)
            return "󰂄";

        const rawPercent = device.percentage;
        const percent = rawPercent <= 1 ? rawPercent * 100 : rawPercent;
        if (percent <= 10)
            return "";

        if (percent <= 35)
            return "";

        if (percent <= 65)
            return "";

        if (percent <= 85)
            return "";

        return "";
    }
    function batteryPercentValue(device) {
        if (!device || !device.ready)
            return 0;

        const rawPercent = device.percentage;
        const percent = rawPercent <= 1 ? rawPercent * 100 : rawPercent;
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
        function toPercent(value) {
            if (!isFinite(value))
                return NaN;

            return value <= 1 ? value * 100 : value;
        }

        if (!device)
            return -1;

        if (!device.ready)
            return -1;

        const healthRaw = device.healthPercentage;
        const health = toPercent(healthRaw);
        if (isFinite(health) && health > 0)
            return Math.round(health);

        // Fallback: if we at least have a full-capacity reading, assume design==full (100%).
        const full = device.energyCapacity;
        if (isFinite(full) && full > 0)
            return 100;

        // As a last resort, derive full from energy + percentage and assume design==full.
        const percent = toPercent(device.percentage);
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

        const rawPercent = device.percentage;
        const percent = rawPercent <= 1 ? rawPercent * 100 : rawPercent;
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
            RowLayout {
                Layout.fillWidth: true
                spacing: Config.space.md

                Item {
                    height: Config.space.xxl * 2
                    width: Config.space.xxl * 2

                    Text {
                        anchors.centerIn: parent
                        color: root.batteryColor(UPower.displayDevice)
                        font.pixelSize: Config.type.headlineLarge.size
                        text: root.batteryIcon(UPower.displayDevice)
                    }
                }
                ColumnLayout {
                    spacing: Config.space.none

                    Text {
                        color: Config.m3.onSurface
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.headlineMedium.size
                        font.weight: Font.Bold
                        text: root.percentLabel(UPower.displayDevice)
                    }
                    Text {
                        color: Config.m3.onSurfaceVariant
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.labelMedium.size
                        text: root.stateLabel(UPower.displayDevice)
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
            }
            ProgressBar {
                Layout.fillWidth: true
                fillColor: root.batteryColor(UPower.displayDevice)
                height: Config.space.xs
                trackColor: Config.moduleBackgroundMuted
                value: root.batteryPercentValue(UPower.displayDevice) / 100
            }

            // Power Mode Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.xs

                Text {
                    Layout.bottomMargin: Config.space.xs
                    color: Config.m3.primary
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.labelSmall.size
                    font.weight: Font.Black
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
