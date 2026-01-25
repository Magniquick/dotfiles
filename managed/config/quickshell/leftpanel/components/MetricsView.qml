pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../common" as Common
import "./" as Components

Item {
    id: root

    // Expose uptime for footer
    readonly property string uptime: sysInfo.uptime || "--"

    property var sysInfo: ({
            cpu: 0,
            mem: 0,
            mem_used: "0.0GB",
            mem_total: "0.0GB",
            disk: 0,
            disk_health: "",
            disk_wear: "",
            temp: 0,
            uptime: "",
            psi_cpu_some: 0,
            psi_cpu_full: 0,
            psi_mem_some: 0,
            psi_mem_full: 0,
            psi_io_some: 0,
            psi_io_full: 0
        })

    function psiBarColor(val, isFull) {
        const baseColor = val >= 25 ? Common.Config.color.error : val >= 5 ? Common.Config.color.secondary : Common.Config.color.primary;
        return isFull ? baseColor : Qt.alpha(baseColor, 0.4);
    }

    readonly property bool isHealthy: sysInfo.psi_cpu_full < 25 && sysInfo.psi_mem_full < 25 && sysInfo.psi_io_full < 25 && tempValue < 85

    readonly property string sysInfoCommand: Quickshell.shellPath("common/scripts/sys_info.sh")
    readonly property real tempValue: Number(sysInfo.temp || 0)
    readonly property color tempColor: tempValue >= 85 ? Common.Config.color.error : (tempValue >= 75 ? Common.Config.color.secondary : Common.Config.color.tertiary)
    readonly property int diskWearPct: parseInt(sysInfo.disk_wear || "", 10)
    readonly property color diskHealthColor: {
        const w = diskWearPct, s = (sysInfo.disk_health || "").toLowerCase();
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

    Process {
        id: proc
        command: ["bash", root.sysInfoCommand]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    // Merge into existing object to avoid resetting values
                    root.sysInfo = Object.assign({}, root.sysInfo, data);
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        // qmllint disable missing-property
        running: root.visible && root.QsWindow.window && root.QsWindow.window.visible
        // qmllint enable missing-property
        onTriggered: if (!proc.running)
            proc.running = true
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
                value: root.sysInfo.cpu
                accent: Common.Config.color.primary
                label: "Processor"
                icon: "\uf4bc"
            }
            Components.CircularGauge {
                value: root.sysInfo.mem
                accent: Common.Config.color.primary
                label: "Memory"
                icon: "\uefc5"
            }
            Components.CircularGauge {
                value: root.sysInfo.disk
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
                value: root.sysInfo.temp + "°C"
                icon: "\uf2c8"
                subtext: "Package Temp"
                accent: root.tempColor
            }

            Components.StatCard {
                title: "Disk Health"
                value: root.sysInfo.disk_health || "Unknown"
                icon: "\udb80\udeca"
                subtext: root.sysInfo.disk_wear ? "Wear: " + root.sysInfo.disk_wear : ""
                accent: root.diskHealthColor
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
                        readonly property real someVal: root.sysInfo["psi_" + key + "_some"] || 0
                        readonly property real fullVal: root.sysInfo["psi_" + key + "_full"] || 0

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: psiDelegate.label
                                color: Common.Config.color.on_surface_variant
                                font {
                                    family: Common.Config.fontFamily
                                    pixelSize: 9
                                    weight: Font.Bold
                                    letterSpacing: 2
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

            // Health status card
            Rectangle {
                Layout.preferredWidth: 100
                Layout.fillHeight: true
                radius: Common.Config.shape.corner.lg
                color: Qt.alpha(Common.Config.color.on_surface, 0.02)
                border.width: 1
                border.color: Qt.alpha(Common.Config.color.on_surface, 0.05)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Common.Config.space.md
                    spacing: Common.Config.space.xs

                    Item {
                        Layout.fillHeight: true
                    }

                    // Status icon with pulse
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        implicitWidth: 40
                        implicitHeight: 40
                        radius: 20
                        color: Qt.alpha(root.isHealthy ? Common.Config.color.tertiary : Common.Config.color.error, 0.1)

                        Text {
                            anchors.centerIn: parent
                            text: root.isHealthy ? "\udb80\udda8" : "\uf071"
                            color: root.isHealthy ? Common.Config.color.tertiary : Common.Config.color.error
                            font.family: Common.Config.iconFontFamily
                            font.pixelSize: 20
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.isHealthy ? "HEALTHY" : "WARNING"
                        color: Common.Config.color.on_surface
                        font {
                            family: Common.Config.fontFamily
                            pixelSize: 10
                            weight: Font.Bold
                            letterSpacing: 2
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.isHealthy ? "All systems go" : "Check metrics"
                        color: Common.Config.color.on_surface_variant
                        font {
                            family: Common.Config.fontFamily
                            pixelSize: 9
                        }
                        opacity: 0.5
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
