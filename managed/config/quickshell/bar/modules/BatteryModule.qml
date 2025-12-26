import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower

ModuleContainer {
    id: root

    property bool showTime: false
    property int healthPercent: -1

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

    function timeLabel(device) {
        if (!device || !device.ready)
            return "";

        const time = device.timeToEmpty > 0 ? device.timeToEmpty : device.timeToFull;
        const formatted = formatSeconds(time);
        return formatted ? formatted : "";
    }

    function percentLabel(device) {
        if (!device || !device.ready)
            return "";

        const rawPercent = device.percentage;
        const percent = rawPercent <= 1 ? rawPercent * 100 : rawPercent;
        return Math.round(percent) + "%";
    }

    function batteryPercentValue(device) {
        if (!device || !device.ready)
            return 0;

        const rawPercent = device.percentage;
        const percent = rawPercent <= 1 ? rawPercent * 100 : rawPercent;
        return Math.max(0, Math.min(100, percent));
    }

    function healthLabel() {
        return root.healthPercent >= 0 ? root.healthPercent + "%" : "—";
    }

    function batteryColor(device) {
        if (!device || !device.ready)
            return Config.textColor;

        if (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge)
            return Config.green;

        if (device.state === UPowerDeviceState.Discharging || device.state === UPowerDeviceState.PendingDischarge)
            return Config.red;

        return Config.textColor;
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

    function tooltipLabel() {
        const device = UPower.displayDevice;
        if (!device || !device.ready)
            return "Battery: unknown";

        const percentText = root.percentLabel(device);
        const timeText = root.timeLabel(device);
        const timeSuffix = timeText ? " (" + timeText + ")" : "";
        return "Battery: " + percentText + timeSuffix;
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

    tooltipTitle: "Battery"
    tooltipText: root.tooltipLabel()
    tooltipHoverable: true
    Component.onCompleted: root.refreshHealth()
    onTooltipActiveChanged: {
        if (root.tooltipActive)
            root.refreshHealth();
    }
    content: [
        IconTextRow {
            spacing: root.contentSpacing
            iconText: root.batteryIcon(UPower.displayDevice)
            iconColor: root.batteryColor(UPower.displayDevice)
            text: root.showTime ? root.timeLabel(UPower.displayDevice) : root.percentLabel(UPower.displayDevice)
            textColor: root.batteryColor(UPower.displayDevice)
        }
    ]

    Connections {
        function onReadyChanged() {
            root.refreshHealth();
        }

        function onHealthPercentageChanged() {
            root.refreshHealth();
        }

        function onEnergyCapacityChanged() {
            root.refreshHealth();
        }

        function onPercentageChanged() {
            root.refreshHealth();
        }

        target: UPower.displayDevice
        ignoreUnknownSignals: true
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.showTime = !root.showTime
    }

    tooltipContent: Component {
        ColumnLayout {
            spacing: Config.space.md
            width: 240 // Match CalendarTooltip width

            // Header Section
            RowLayout {
                Layout.fillWidth: true
                spacing: Config.space.md

                Item {
                    width: Config.space.xxl * 2
                    height: Config.space.xxl * 2

                    Text {
                        anchors.centerIn: parent
                        text: root.batteryIcon(UPower.displayDevice)
                        font.pixelSize: Config.type.headlineLarge.size
                        color: root.batteryColor(UPower.displayDevice)
                    }
                }

                ColumnLayout {
                    spacing: Config.space.none

                    Text {
                        text: root.percentLabel(UPower.displayDevice)
                        color: Config.textColor
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.headlineMedium.size
                        font.weight: Font.Bold
                    }

                    Text {
                        text: root.stateLabel(UPower.displayDevice)
                        color: Config.textMuted
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.labelMedium.size
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            ProgressBar {
                Layout.fillWidth: true
                height: Config.space.xs
                value: root.batteryPercentValue(UPower.displayDevice) / 100
                fillColor: root.batteryColor(UPower.displayDevice)
                trackColor: Config.moduleBackgroundMuted
            }

            // Power Mode Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.xs

                Text {
                    text: "POWER PROFILE"
                    color: Config.primary
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.labelSmall.size
                    font.weight: Font.Black
                    Layout.bottomMargin: Config.space.xs
                }

                TooltipActionsRow {
                    spacing: Config.space.sm

                    ActionChip {
                        text: "󰾆"
                        active: PowerProfiles.profile === PowerProfile.PowerSaver
                        onClicked: PowerProfiles.profile = PowerProfile.PowerSaver
                        Layout.fillWidth: true
                    }

                    ActionChip {
                        text: "󰾅"
                        active: PowerProfiles.profile === PowerProfile.Balanced
                        onClicked: PowerProfiles.profile = PowerProfile.Balanced
                        Layout.fillWidth: true
                    }

                    ActionChip {
                        text: ""
                        active: PowerProfiles.profile === PowerProfile.Performance
                        onClicked: PowerProfiles.profile = PowerProfile.Performance
                        Layout.fillWidth: true
                    }
                }
            }

            // Health Section
            InfoRow {
                label: "Battery Health"
                value: root.healthLabel()
                icon: "󰁹"
                Layout.fillWidth: true
                opacity: 0.6
                showLeader: false
            }
        }
    }
}
