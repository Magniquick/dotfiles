import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../components/JsonUtils.js" as JsonUtils

ModuleContainer {
  id: root
  contentSpacing: 8
  property bool micActive: false
  property bool cameraActive: false
  property bool screenActive: false
  property bool locationActive: false
  property string micApps: ""
  property string cameraApps: ""
  property string screenApps: ""
  property string locationApps: ""
  property string statusTooltip: "Privacy: idle"
  property string micIcon: ""
  property string cameraIcon: ""
  property string screenIcon: "󰍹"
  property string locationIcon: ""
  property color micColor: Config.green
  property color cameraColor: Config.yellow
  property color screenColor: Config.accent
  property color locationColor: Config.lavender
  readonly property string scriptPath: Quickshell.shellPath("modules/privacy/privacy_dots.sh")
  tooltipTitle: "Privacy"
  tooltipText: root.statusTooltip
  tooltipHoverable: true
  tooltipContent: Component {
    ColumnLayout {
      spacing: Config.space.sm

      TooltipCard {
        content: [
          InfoRow {
            label: "Mic"
            value: root.appLabel(root.micApps)
            valueColor: root.micActive ? root.micColor : Config.textMuted
          },
          InfoRow {
            label: "Camera"
            value: root.appLabel(root.cameraApps)
            valueColor: root.cameraActive ? root.cameraColor : Config.textMuted
          },
          InfoRow {
            label: "Location"
            value: root.appLabel(root.locationApps)
            valueColor: root.locationActive ? root.locationColor : Config.textMuted
          },
          InfoRow {
            label: "Screen"
            value: root.appLabel(root.screenApps)
            valueColor: root.screenActive ? root.screenColor : Config.textMuted
          }
        ]
      }

      TooltipActionsRow {
        ActionChip {
          text: "Refresh"
          onClicked: privacyRunner.trigger()
        }
      }
    }
  }
  collapsed: !root.micActive && !root.cameraActive && !root.screenActive && !root.locationActive

  function buildStatus(label, apps) {
    return apps !== "" ? label + ": " + apps : label + ": off"
  }

  function appLabel(apps) {
    if (!apps || apps.trim() === "")
      return "Off"
    return root.truncateApps(apps.trim())
  }

  function truncateApps(apps) {
    if (apps.length <= 32)
      return apps
    return apps.slice(0, 29) + "..."
  }

  function updateTooltip() {
    const micStatus = root.buildStatus("Mic", root.micApps)
    const camStatus = root.buildStatus("Cam", root.cameraApps)
    const locStatus = root.buildStatus("Location", root.locationApps)
    const scrStatus = root.buildStatus("Screen sharing", root.screenApps)
    root.statusTooltip = micStatus + "  |  " + camStatus + "  |  " + locStatus + "  |  " + scrStatus
  }

  function updateFromPayload(payload) {
    if (!payload || typeof payload !== "object") {
      root.micActive = false
      root.cameraActive = false
      root.screenActive = false
      root.locationActive = false
      root.micApps = ""
      root.cameraApps = ""
      root.screenApps = ""
      root.locationApps = ""
      root.updateTooltip()
      return
    }
    root.micActive = payload.mic === 1 || payload.mic === true
    root.cameraActive = payload.cam === 1 || payload.cam === true
    root.screenActive = payload.scr === 1 || payload.scr === true
    root.locationActive = payload.loc === 1 || payload.loc === true
    root.micApps = payload.mic_app ? String(payload.mic_app).trim() : ""
    root.cameraApps = payload.cam_app ? String(payload.cam_app).trim() : ""
    root.screenApps = payload.scr_app ? String(payload.scr_app).trim() : ""
    root.locationApps = payload.loc_app ? String(payload.loc_app).trim() : ""
    root.updateTooltip()
  }

  CommandRunner {
    id: privacyRunner
    intervalMs: 3000
    command: root.scriptPath
    onRan: function(output) {
      root.updateFromPayload(JsonUtils.parseObject(output))
    }
  }

  content: [
    Row {
      spacing: root.contentSpacing

      IconLabel {
        text: root.micIcon
        color: root.micColor
        visible: root.micActive
      }
      IconLabel {
        text: root.cameraIcon
        color: root.cameraColor
        visible: root.cameraActive
      }
      IconLabel {
        text: root.locationIcon
        color: root.locationColor
        visible: root.locationActive
      }
      IconLabel {
        text: root.screenIcon
        color: root.screenColor
        visible: root.screenActive
      }
    }
  ]
}
