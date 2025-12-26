pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../components/JsonUtils.js" as JsonUtils

ModuleContainer {
    id: root
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
    readonly property int diskWearPct: parseInt(root.sysInfo.disk_wear || "", 10)
    readonly property color diskHealthColor: {
        const wearPct = root.diskWearPct;
        const status = (root.sysInfo.disk_health || "").toLowerCase();
        if (!isNaN(wearPct)) {
            if (wearPct >= 90)
                return Config.red;
            if (wearPct >= 75)
                return Config.yellow;
        }
        if (status.startsWith("healthy") || status.startsWith("passed"))
            return Config.green;
        if (status === "" || status.indexOf("unknown") !== -1)
            return Config.yellow;
        return Config.red;
    }
    readonly property string diskLifeLabel: {
        const wearPct = root.diskWearPct;
        if (!isNaN(wearPct)) {
            const remaining = Math.max(0, 100 - wearPct);
            return remaining + "% life left";
        }
        return "Life unknown";
    }
    readonly property string diskHealthBadgeText: root.sysInfo.disk_health || "Unknown"
    readonly property color diskHealthBadgeColor: Qt.rgba(root.diskHealthColor.r, root.diskHealthColor.g, root.diskHealthColor.b, 0.12)
    readonly property color diskHealthBadgeTextColor: root.diskHealthColor
    readonly property string diskUsedLabel: root.sysInfo.disk + "% used"
    readonly property string diskRemainingLabel: root.diskLifeLabel
    readonly property real tempValue: Number(root.sysInfo.temp || 0)
    readonly property color tempColor: tempValue >= 85 ? Config.red : (tempValue >= 75 ? Config.yellow : Config.green)
    readonly property string tempStatus: tempValue >= 85 ? "Critical" : (tempValue >= 75 ? "Hot" : (tempValue >= 60 ? "Warm" : "Cool"))
    readonly property string tempRisk: tempValue >= 85 ? "Throttle risk high" : (tempValue >= 75 ? "Watch temps" : "Stable")

    tooltipTitle: "System"
    tooltipSubtitle: root.lastUpdated !== "" ? ("Updated " + root.lastUpdated) : ""
    tooltipHoverable: true
    tooltipShowRefreshIcon: true
    tooltipRefreshing: sysInfoRunner.running
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
                            Layout.preferredWidth: Config.space.xxl * 2 - Config.space.xs
                            Layout.preferredHeight: Config.space.xxl * 2 - Config.space.xs
                            Text {
                                anchors.centerIn: parent
                                text: "󰣇"
                                font.family: Config.iconFontFamily
                                font.pixelSize: Config.type.headlineLarge.size
                                color: Config.lavender
                                renderType: Text.NativeRendering
                                antialiasing: true
                            }
                        }

                        ColumnLayout {
                            spacing: Config.space.none
                            Layout.fillWidth: true

                            Text {
                                text: "Arch Linux"
                                color: Config.textColor
                                font.family: Config.fontFamily
                                font.pixelSize: Config.type.titleSmall.size
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: root.sysInfo.uptime !== "" ? ("Up " + root.sysInfo.uptime) : "Hover for live vitals"
                                color: Config.textMuted
                                font.family: Config.fontFamily
                                font.pixelSize: Config.type.bodySmall.size
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        Item {
                            Layout.preferredWidth: 0
                        }
                    }
                ]
            }

            TooltipCard {
                outlined: true
                borderColor: Qt.rgba(1, 1, 1, 0.08)
                backgroundColor: Config.surfaceContainerHigh
                padding: Config.space.md
                spacing: Config.space.sm
                content: [
                    Text {
                        text: "VITALS"
                        color: Config.lavender
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.labelSmall.size
                        font.weight: Font.Black
                        font.letterSpacing: 1.5
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
                                    text: "CPU"
                                    color: Config.textColor
                                    font.family: Config.fontFamily
                                    font.pixelSize: Config.type.bodySmall.size
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: root.sysInfo.cpu.toFixed(1) + "%"
                                    color: Config.info
                                    font.family: Config.fontFamily
                                    font.pixelSize: Config.type.bodySmall.size
                                    font.weight: Font.DemiBold
                                }
                            }

                            ProgressBar {
                                Layout.fillWidth: true
                                height: Config.space.xs + Config.spaceHalfXs
                                value: root.sysInfo.cpu / 100
                                fillColor: Config.info
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Config.space.xs

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "Memory"
                                    color: Config.textColor
                                    font.family: Config.fontFamily
                                    font.pixelSize: Config.type.bodySmall.size
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: root.sysInfo.mem_used + " / " + root.sysInfo.mem_total
                                    color: Config.lavender
                                    font.family: Config.fontFamily
                                    font.pixelSize: Config.type.bodySmall.size
                                    font.weight: Font.DemiBold
                                }
                            }

                            ProgressBar {
                                Layout.fillWidth: true
                                height: Config.space.xs + Config.spaceHalfXs
                                value: root.sysInfo.mem / 100
                                fillColor: Config.lavender
                            }
                        }
                    }
                ]
            }

            GridLayout {
                columns: 2
                rowSpacing: Config.space.sm
                columnSpacing: Config.space.sm
                Layout.fillWidth: true

                MetricBlock {
                    label: "DISK"
                    value: root.diskUsedLabel
                    secondaryValue: root.diskRemainingLabel
                    icon: "󰋊"
                    fillRatio: root.sysInfo.disk / 100
                    accentColor: root.diskHealthColor
                    labelColor: Config.lavender
                    chipText: root.diskHealthBadgeText
                    chipColor: Qt.rgba(root.diskHealthColor.r, root.diskHealthColor.g, root.diskHealthColor.b, 0.22)
                    chipTextColor: Config.textMuted
                    valueColor: Config.textColor
                    backgroundColor: Config.surfaceContainerHigh
                    borderColor: Qt.rgba(1, 1, 1, 0.12)
                    borderWidth: 1
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    padding: Config.space.md - Config.spaceHalfXs
                }

                MetricBlock {
                    label: "TEMP"
                    value: root.sysInfo.temp + "°C"
                    secondaryValue: root.tempRisk
                    icon: "󰔄"
                    fillRatio: Math.min(1, root.tempValue / 100)
                    accentColor: root.tempColor
                    labelColor: Config.lavender
                    chipText: root.tempStatus
                    chipColor: Qt.rgba(root.tempColor.r, root.tempColor.g, root.tempColor.b, 0.22)
                    chipTextColor: Config.textMuted
                    backgroundColor: Config.surfaceContainerHigh
                    borderColor: Qt.rgba(1, 1, 1, 0.12)
                    borderWidth: 1
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    padding: Config.space.md - Config.spaceHalfXs
                }
            }
        }
    }

    CommandRunner {
        id: sysInfoRunner
        intervalMs: 2000
        enabled: root.tooltipActive
        command: root.sysInfoCommand
        onRan: function (output) {
            const data = JsonUtils.parseObject(output);
            if (data)
                root.sysInfo = data;

            root.lastUpdated = Qt.formatDateTime(new Date(), "hh:mm ap");
        }
        onEnabledChanged: {
            if (enabled)
                trigger();
        }
    }

    Connections {
        target: root
        function onTooltipRefreshRequested() {
            sysInfoRunner.trigger();
        }
    }

    content: [
        IconLabel {
            text: root.iconText
            color: Config.lavender
            renderType: Text.NativeRendering
            antialiasing: true
        }
    ]

    MouseArea {
        anchors.fill: parent
        onClicked: Quickshell.execDetached(["quickshell", "ipc", "call", "powermenu", "toggle"])
    }
}
