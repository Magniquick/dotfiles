/**
 * @module ArchIconModule
 * @description System information module with Arch Linux branding
 *
 * Features:
 * - Displays Arch Linux icon in bar
 * - Tooltip shows live system vitals (CPU, memory, disk, temperature)
 * - Disk health monitoring with wear level tracking
 * - Temperature monitoring with throttle risk indicators
 * - Click opens powermenu
 *
 * Dependencies:
 * - bar/scripts/sys_info.sh: Shell script providing system metrics as JSON
 *
 * Configuration:
 * - iconText: Custom icon (default: Arch logo)
 * - Polling: 2s interval while tooltip is open
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../components/JsonUtils.js" as JsonUtils

ModuleContainer {
    id: root

    readonly property color diskHealthBadgeColor: Qt.alpha(root.diskHealthColor, 0.12)
    readonly property string diskHealthBadgeText: root.sysInfo.disk_health || "Unknown"
    readonly property color diskHealthBadgeTextColor: root.diskHealthColor
    readonly property color diskHealthColor: {
        const wearPct = root.diskWearPct;
        const status = (root.sysInfo.disk_health || "").toLowerCase();
        if (!isNaN(wearPct)) {
            if (wearPct >= 90)
                return Config.m3.error;
            if (wearPct >= 75)
                return Config.m3.warning;
        }
        if (status.startsWith("healthy") || status.startsWith("passed"))
            return Config.m3.success;
        if (status === "" || status.indexOf("unknown") !== -1)
            return Config.m3.warning;
        return Config.m3.error;
    }
    readonly property string diskLifeLabel: {
        const wearPct = root.diskWearPct;
        if (!isNaN(wearPct)) {
            const remaining = Math.max(0, 100 - wearPct);
            return remaining + "% life left";
        }
        return "Life unknown";
    }
    readonly property string diskRemainingLabel: root.diskLifeLabel
    readonly property string diskUsedLabel: root.sysInfo.disk + "% used"
    readonly property int diskWearPct: parseInt(root.sysInfo.disk_wear || "", 10)
    property string iconText: ""
    property string lastUpdated: ""
    property var sysInfo: ({
            cpu: 0,
            mem: 0,
            mem_used: "0.0GB",
            mem_total: "0.0GB",
            disk: 0,
            disk_health: "",
            disk_wear: "",
            temp: 0,
            uptime: ""
        })
    readonly property string sysInfoCommand: Quickshell.shellPath(((Quickshell.shellDir || "").endsWith("/bar") ? "" : "bar/") + "scripts/sys_info.sh")
    readonly property color tempColor: tempValue >= 85 ? Config.m3.error : (tempValue >= 75 ? Config.m3.warning : Config.m3.success)
    readonly property string tempRisk: tempValue >= 85 ? "Throttle risk high" : (tempValue >= 75 ? "Watch temps" : "Stable")
    readonly property string tempStatus: tempValue >= 85 ? "Critical" : (tempValue >= 75 ? "Hot" : (tempValue >= 60 ? "Warm" : "Cool"))
    readonly property real tempValue: Number(root.sysInfo.temp || 0)

    tooltipHoverable: true
    tooltipRefreshing: sysInfoRunner.running
    tooltipShowRefreshIcon: true
    tooltipSubtitle: root.lastUpdated !== "" ? ("Updated " + root.lastUpdated) : ""
    tooltipTitle: "System"

    content: [
        IconLabel {
            antialiasing: true
            color: Config.m3.tertiary
            renderType: Text.NativeRendering
            text: root.iconText
        }
    ]
    tooltipContent: Component {
        ColumnLayout {
            spacing: Config.space.md
            width: 280

            TooltipCard {
                backgroundColor: "transparent"
                outlined: false
                padding: Config.space.none
                spacing: Config.space.md

                content: [
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Config.space.md

                        Item {
                            Layout.preferredHeight: Config.space.xxl * 2 - Config.space.xs
                            Layout.preferredWidth: Config.space.xxl * 2 - Config.space.xs

                            Text {
                                anchors.centerIn: parent
                                antialiasing: true
                                color: Config.m3.tertiary
                                font.family: Config.iconFontFamily
                                font.pixelSize: Config.type.headlineLarge.size
                                renderType: Text.NativeRendering
                                text: "󰣇"
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Config.space.none

                            Text {
                                Layout.fillWidth: true
                                color: Config.m3.onSurface
                                elide: Text.ElideRight
                                font.family: Config.fontFamily
                                font.pixelSize: Config.type.titleSmall.size
                                font.weight: Font.Bold
                                text: "Arch Linux"
                            }
                            Text {
                                Layout.fillWidth: true
                                color: Config.m3.onSurfaceVariant
                                elide: Text.ElideRight
                                font.family: Config.fontFamily
                                font.pixelSize: Config.type.bodySmall.size
                                text: root.sysInfo.uptime !== "" ? ("Up " + root.sysInfo.uptime) : "Hover for live vitals"
                            }
                        }
                        Item {
                            Layout.preferredWidth: 0
                        }
                    }
                ]
            }
            TooltipCard {
                backgroundColor: Config.m3.surfaceContainerHigh
                borderColor: Qt.alpha(Config.m3.onSurface, 0.08)
                outlined: true
                padding: Config.space.md
                spacing: Config.space.sm

                content: [
                    Text {
                        color: Config.m3.tertiary
                        font.family: Config.fontFamily
                        font.letterSpacing: 1.5
                        font.pixelSize: Config.type.labelSmall.size
                        font.weight: Font.Black
                        text: "VITALS"
                    },
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Config.space.sm

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Config.space.xs

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    color: Config.m3.onSurface
                                    font.family: Config.fontFamily
                                    font.pixelSize: Config.type.bodySmall.size
                                    text: "CPU"
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                                Text {
                                    color: Config.m3.info
                                    font.family: Config.fontFamily
                                    font.pixelSize: Config.type.bodySmall.size
                                    font.weight: Font.DemiBold
                                    text: root.sysInfo.cpu.toFixed(1) + "%"
                                }
                            }
                            ProgressBar {
                                Layout.fillWidth: true
                                fillColor: Config.m3.info
                                height: Config.space.xs + Config.spaceHalfXs
                                value: root.sysInfo.cpu / 100
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Config.space.xs

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    color: Config.m3.onSurface
                                    font.family: Config.fontFamily
                                    font.pixelSize: Config.type.bodySmall.size
                                    text: "Memory"
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                                Text {
                                    color: Config.m3.tertiary
                                    font.family: Config.fontFamily
                                    font.pixelSize: Config.type.bodySmall.size
                                    font.weight: Font.DemiBold
                                    text: root.sysInfo.mem_used + " / " + root.sysInfo.mem_total
                                }
                            }
                            ProgressBar {
                                Layout.fillWidth: true
                                fillColor: Config.m3.tertiary
                                height: Config.space.xs + Config.spaceHalfXs
                                value: root.sysInfo.mem / 100
                            }
                        }
                    }
                ]
            }
            GridLayout {
                Layout.fillWidth: true
                columnSpacing: Config.space.sm
                columns: 2
                rowSpacing: Config.space.sm

                MetricBlock {
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    accentColor: root.diskHealthColor
                    backgroundColor: Config.m3.surfaceContainerHigh
                    borderColor: Qt.alpha(Config.m3.onSurface, 0.12)
                    borderWidth: 1
                    chipColor: Qt.alpha(root.diskHealthColor, 0.22)
                    chipText: root.diskHealthBadgeText
                    chipTextColor: Config.m3.onSurfaceVariant
                    fillRatio: root.sysInfo.disk / 100
                    icon: "󰋊"
                    label: "DISK"
                    labelColor: Config.m3.tertiary
                    padding: Config.space.md - Config.spaceHalfXs
                    secondaryValue: root.diskRemainingLabel
                    value: root.diskUsedLabel
                    valueColor: Config.m3.onSurface
                }
                MetricBlock {
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    accentColor: root.tempColor
                    backgroundColor: Config.m3.surfaceContainerHigh
                    borderColor: Qt.alpha(Config.m3.onSurface, 0.12)
                    borderWidth: 1
                    chipColor: Qt.alpha(root.tempColor, 0.22)
                    chipText: root.tempStatus
                    chipTextColor: Config.m3.onSurfaceVariant
                    fillRatio: Math.min(1, root.tempValue / 100)
                    icon: "󰔄"
                    label: "TEMP"
                    labelColor: Config.m3.tertiary
                    padding: Config.space.md - Config.spaceHalfXs
                    secondaryValue: root.tempRisk
                    value: root.sysInfo.temp + "°C"
                }
            }
        }
    }

    CommandRunner {
        id: sysInfoRunner

        command: root.sysInfoCommand
        enabled: root.tooltipActive
        intervalMs: 2000

        onEnabledChanged: {
            if (enabled)
                trigger();
        }
        onRan: function (output) {
            const data = JsonUtils.parseObject(output);
            if (data)
                root.sysInfo = data;

            root.lastUpdated = Qt.formatDateTime(new Date(), "hh:mm ap");
        }
    }
    Connections {
        function onTooltipRefreshRequested() {
            sysInfoRunner.trigger();
        }

        target: root
    }

    onClicked: {
        Quickshell.execDetached(["quickshell", "--path", Quickshell.env("HOME") + "/.config/quickshell/powermenu/"]);
    }
}
