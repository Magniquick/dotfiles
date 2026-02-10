pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../common" as Common
import "./" as Components
import qsnative

Item {
    id: root

    // Expose uptime for footer
    readonly property string uptime: sysInfoProvider.uptime || "--"

    function psiBarColor(val, isFull) {
        const baseColor = val >= 25 ? Common.Config.color.error : val >= 5 ? Common.Config.color.secondary : Common.Config.color.primary;
        return isFull ? baseColor : Qt.alpha(baseColor, 0.4);
    }

    readonly property bool isHealthy: sysInfoProvider.psi_cpu_full < 25 && sysInfoProvider.psi_mem_full < 25 && sysInfoProvider.psi_io_full < 25 && tempValue < 85

    readonly property real tempValue: Number(sysInfoProvider.temp || 0)
    readonly property color tempColor: tempValue >= 85 ? Common.Config.color.error : (tempValue >= 75 ? Common.Config.color.secondary : Common.Config.color.tertiary)
    readonly property int diskWearPct: parseInt(sysInfoProvider.disk_wear || "", 10)
    readonly property color diskHealthColor: {
        const w = diskWearPct, s = (sysInfoProvider.disk_health || "").toLowerCase();
        if (!isNaN(w)) {
            if (w >= 90)
                return Common.Config.color.error;
            if (w >= 75)
                return Common.Config.color.secondary;
        }
        if (s.startsWith("healthy") || s.startsWith("passed"))
            return Common.Config.color.tertiary;
        return s === "" || s.includes("unknown") ? Common.Config.color.secondary : Common.Config.color.error;
    }

    SysInfoProvider {
        id: sysInfoProvider
    }

    Timer {
        id: cpuPrimeTimer
        interval: 200
        repeat: false
        running: false
        onTriggered: sysInfoProvider.refresh()
    }

    Timer {
        id: pollTimer
        interval: 2000
        repeat: true
        triggeredOnStart: true
        // qmllint disable missing-property
        running: root.visible && root.QsWindow.window && root.QsWindow.window.visible
        // qmllint enable missing-property
        onTriggered: sysInfoProvider.refresh()
        onRunningChanged: {
            if (running) {
                // CPU% needs a previous /proc/stat sample; take an early second sample so we
                // don't wait the full 2s for the first "real" value.
                cpuPrimeTimer.restart();
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Common.Config.space.lg
        spacing: Common.Config.space.xl

        // Gauges
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 130
            spacing: Common.Config.space.sm

            Components.CircularGauge {
                value: sysInfoProvider.cpu
                accent: Common.Config.color.primary
                label: "Processor"
                icon: "\uf4bc"
            }
            Components.CircularGauge {
                value: sysInfoProvider.mem
                accent: Common.Config.color.primary
                label: "Memory"
                icon: "\uefc5"
            }
            Components.CircularGauge {
                value: sysInfoProvider.disk
                accent: root.diskHealthColor
                label: "Storage"
                icon: "\udb80\udeca"
            }
        }

        // Stats row
        RowLayout {
            Layout.fillWidth: true
            spacing: Common.Config.space.sm

            Components.StatCard {
                title: "Thermal"
                value: sysInfoProvider.temp + "°C"
                icon: "\uf2c8"
                subtext: "Package Temp"
                accent: root.tempColor
                centerContent: true
            }

            Components.StatCard {
                title: "Disk Health"
                value: sysInfoProvider.disk_health || "Unknown"
                icon: "\udb80\udeca"
                subtext: sysInfoProvider.disk_wear ? "Wear: " + sysInfoProvider.disk_wear : ""
                accent: root.diskHealthColor
                centerContent: true
            }
        }

        // Pressure + Health grid
        RowLayout {
            Layout.fillWidth: true
            spacing: Common.Config.space.lg

            // Pressure bars column
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Common.Config.space.md

                Repeater {
                    model: ["cpu", "mem", "io"]

                    ColumnLayout {
                        id: psiDelegate
                        required property string modelData
                        Layout.fillWidth: true
                        spacing: 2

                        readonly property string key: psiDelegate.modelData
                        readonly property string label: key === "cpu" ? "CPU" : (key === "mem" ? "MEM" : "I/O")
                        readonly property real someVal: sysInfoProvider["psi_" + key + "_some"] || 0
                        readonly property real fullVal: sysInfoProvider["psi_" + key + "_full"] || 0

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: psiDelegate.label
                                color: Common.Config.color.on_surface_variant
                                font {
                                    family: Common.Config.fontFamily
                                    pixelSize: 9
                                    weight: Font.Bold
                                }
                                opacity: 0.5
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            // Show both values
                            Text {
                                text: psiDelegate.someVal.toFixed(1)
                                color: Common.Config.color.on_surface_variant
                                font {
                                    family: Common.Config.fontFamily
                                    pixelSize: 9
                                }
                                opacity: 0.6
                            }
                            Text {
                                text: " / "
                                color: Common.Config.color.on_surface_variant
                                font {
                                    family: Common.Config.fontFamily
                                    pixelSize: 9
                                }
                                opacity: 0.4
                            }
                            Text {
                                text: psiDelegate.fullVal.toFixed(1) + "%"
                                color: Common.Config.color.on_surface
                                font {
                                    family: Common.Config.fontFamily
                                    pixelSize: 10
                                    weight: Font.Bold
                                }
                            }
                        }

                        // Stacked bars
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 10
                            implicitHeight: 10
                            radius: 5
                            color: Qt.alpha(Common.Config.color.on_surface, 0.05)
                            border.width: 1
                            border.color: Qt.alpha(Common.Config.color.on_surface, 0.05)
                            clip: true

                            // "some" bar (dull, behind)
                            Rectangle {
                                width: Math.min(psiDelegate.someVal, 100) / 100 * parent.width
                                height: parent.height
                                radius: 5
                                color: root.psiBarColor(psiDelegate.someVal, false)

                                Behavior on width {
                                    NumberAnimation {
                                        duration: 1000
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }

                            // "full" bar (bright, in front)
                            Rectangle {
                                width: Math.min(psiDelegate.fullVal, 100) / 100 * parent.width
                                height: parent.height
                                radius: 5
                                color: root.psiBarColor(psiDelegate.fullVal, true)

                                Behavior on width {
                                    NumberAnimation {
                                        duration: 1000
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // (Health card removed; footer already reflects health state.)
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
