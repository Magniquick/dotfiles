import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../common" as Common
import "./" as Components

Item {
  id: root

  property var sysInfo: ({
    cpu: 0, mem: 0, mem_used: "0.0GB", mem_total: "0.0GB",
    disk: 0, disk_health: "", disk_wear: "", temp: 0, uptime: "",
    psi_cpu: 0, psi_mem: 0, psi_io: 0
  })

  readonly property color colorTeal: "#94e2d5"
  readonly property color colorPeach: "#fab387"
  readonly property color colorRed: "#f38ba8"

  function psiColor(val) {
    if (val >= 20) return colorRed;
    if (val >= 5) return colorPeach;
    return colorTeal;
  }

  readonly property string sysInfoCommand: Quickshell.shellPath("../bar/scripts/sys_info.sh")
  readonly property real tempValue: Number(sysInfo.temp || 0)
  readonly property color tempColor: tempValue >= 80 ? colorRed : (tempValue >= 65 ? colorPeach : colorTeal)
  readonly property int diskWearPct: parseInt(sysInfo.disk_wear || "", 10)
  readonly property color diskHealthColor: {
    const w = diskWearPct, s = (sysInfo.disk_health || "").toLowerCase();
    if (!isNaN(w)) { if (w >= 90) return colorRed; if (w >= 75) return colorPeach; }
    if (s.startsWith("healthy") || s.startsWith("passed")) return Common.Config.m3.success;
    return s === "" || s.includes("unknown") ? colorPeach : colorRed;
  }

  Process {
    id: proc
    command: ["bash", root.sysInfoCommand]
    stdout: StdioCollector {
      onStreamFinished: { try { root.sysInfo = JSON.parse(text); } catch(e) {} }
    }
  }

  Timer {
    interval: 2000; repeat: true; triggeredOnStart: true
    running: root.QsWindow.window?.visible ?? false
    onTriggered: if (!proc.running) proc.running = true
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Common.Config.space.md
    spacing: Common.Config.space.md

    // Compact Header
    RowLayout {
      Layout.fillWidth: true
      spacing: Common.Config.space.sm

      Components.StatCard {
        compact: true
        title: "Uptime"
        value: root.sysInfo.uptime || "--"
        icon: "\uf46e"
        accent: Common.Config.m3.primary
      }

      Components.StatCard {
        compact: true
        title: "Temp"
        value: root.sysInfo.temp + "°C"
        icon: "\udb81\udcf5"
        accent: root.tempColor
      }
    }

    // Main Grid
    GridLayout {
      columns: 3
      Layout.fillWidth: true
      rowSpacing: Common.Config.space.sm
      columnSpacing: Common.Config.space.sm

      Components.CircularGauge {
        value: root.sysInfo.cpu
        accent: Common.Config.m3.info
        label: "CPU"
        subValue: "Usage"
      }

      Components.CircularGauge {
        value: root.sysInfo.mem
        accent: Common.Config.m3.secondary
        label: "Memory"
        subValue: root.sysInfo.mem_used
      }

      Components.CircularGauge {
        value: root.sysInfo.disk
        accent: root.diskHealthColor
        label: "Disk"
        subValue: root.sysInfo.disk_wear ? root.sysInfo.disk_wear + " worn" : "Storage"
      }
    }

    // PSI Section
    Rectangle {
      Layout.fillWidth: true
      implicitHeight: psiCol.implicitHeight + Common.Config.space.md * 2
      color: Common.Config.m3.surfaceContainerHigh
      radius: Common.Config.shape.corner.md
      border.width: 1
      border.color: Common.Config.m3.outline
      opacity: 0.9

      ColumnLayout {
        id: psiCol
        anchors.fill: parent
        anchors.margins: Common.Config.space.md
        spacing: Common.Config.space.sm

        RowLayout {
          Layout.fillWidth: true
          Text {
            text: "Pressure Stall Information (PSI)"
            color: Common.Config.textMuted
            font { family: Common.Config.fontFamily; pixelSize: 9; weight: Font.Black; letterSpacing: 1; capitalization: Font.AllUppercase }
          }
          Item { Layout.fillWidth: true }
          Text {
            text: "10s avg"
            color: Common.Config.textMuted
            font { family: Common.Config.fontFamily; pixelSize: 8; weight: Font.Medium }
            opacity: 0.6
          }
        }

        Repeater {
          model: [
            { l: "CPU", v: root.sysInfo.psi_cpu, i: "\uf2db" },
            { l: "Memory", v: root.sysInfo.psi_mem, i: "\uf538" },
            { l: "I/O", v: root.sysInfo.psi_io, i: "\uf0a0" }
          ]

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
              Layout.fillWidth: true
              Text {
                text: modelData.l
                color: Common.Config.textColor
                font { family: Common.Config.fontFamily; pixelSize: 10; weight: Font.Medium }
              }
              Item { Layout.fillWidth: true }
              Text {
                text: modelData.v.toFixed(2) + "%"
                color: root.psiColor(modelData.v)
                font { family: Common.Config.fontFamily; pixelSize: 10; weight: Font.Bold }
              }
            }

            Rectangle {
              Layout.fillWidth: true
              height: 4
              radius: 2
              color: Common.Config.m3.surfaceVariant

              Rectangle {
                width: Math.min(modelData.v, 100) / 100 * parent.width
                height: parent.height
                radius: 2
                color: root.psiColor(modelData.v)

                Behavior on width {
                  enabled: root.QsWindow.window?.visible ?? false
                  NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                }
              }
            }
          }
        }
      }
    }

    Item { Layout.fillHeight: true }
  }
}
