import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../components"
import "../components/JsonUtils.js" as JsonUtils

ModuleContainer {
  id: root
  property bool moduleAvailable: false
  property bool hasUpdates: false
  property string updatedIcon: ""
  property string updatesIcon: ""
  property string text: "0"
  property string updatesTooltip: "System up to date"
  readonly property string updatesTooltipMarkup: JsonUtils.formatTooltip(root.updatesTooltip)
  property string lastCheckedLabel: ""
  property string onClickCommand: "runapp kitty -o tab_bar_style=hidden --class yay -e yay -Syu"
  readonly property string updatesCommand: "waybar-module-pacman-updates --tooltip-align-columns " +
    "--no-zero-output --interval-seconds 30 --network-interval-seconds 300"
  readonly property string loginShell: {
    const shellValue = Quickshell.env("SHELL")
    return shellValue && shellValue !== "" ? shellValue : "sh"
  }
  tooltipTitle: "Updates"
  tooltipHoverable: true
  tooltipContent: Component {
    ColumnLayout {
      spacing: Config.space.sm

      TooltipCard {
        content: [
          Text {
            id: text
            text: root.updatesTooltipMarkup
            color: Config.textColor
            font.family: Config.fontFamily
            font.pixelSize: Config.fontSize
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            Layout.preferredWidth: 320
            Layout.maximumWidth: 360
          },
          InfoRow {
            label: "Last check"
            value: root.lastCheckedLabel !== "" ? root.lastCheckedLabel : "—"
          }
        ]
      }

      TooltipActionsRow {
        ActionChip {
          text: root.hasUpdates ? "Update" : "Open"
          onClicked: Quickshell.execDetached(["sh", "-c", root.onClickCommand])
        }
      }
    }
  }
  tooltipText: root.hasUpdates ? root.updatesTooltip : "System up to date"
  collapsed: !root.moduleAvailable || (!root.hasUpdates && root.updatedIcon === "")

  function normalizeClassList(value) {
    if (!value)
      return []
    if (Array.isArray(value))
      return value
    if (typeof value === "string")
      return [value]
    return []
  }

  function markNoUpdates() {
    root.hasUpdates = false
    root.text = ""
    root.updatesTooltip = "System up to date"
  }

  function updateFromPayloadText(payloadText) {
    root.recordCheck()
    if (!payloadText) {
      root.markNoUpdates()
      return
    }
    const trimmed = payloadText.trim()
    if (trimmed === "") {
      root.markNoUpdates()
      return
    }
    const payload = JsonUtils.parseObject(trimmed)
    if (!payload || typeof payload !== "object") {
      const count = parseInt(trimmed, 10)
      if (isFinite(count) && count > 0) {
        root.hasUpdates = true
        root.text = String(count)
        root.updatesTooltip = root.text + " updates"
      } else {
        root.markNoUpdates()
      }
      return
    }
    const textValue = payload.text ? String(payload.text).trim() : ""
    const altValue = payload.alt ? String(payload.alt).trim() : ""
    const classNames = root.normalizeClassList(payload.class)
    const classHasUpdates = classNames.indexOf("has-updates") >= 0 || altValue === "has-updates"
    const classUpdated = classNames.indexOf("updated") >= 0 || altValue === "updated"
    const hasTextUpdates = textValue !== "" && textValue !== "0"
    root.hasUpdates = classHasUpdates || (hasTextUpdates && !classUpdated)
    root.text = root.hasUpdates ? textValue : ""
    if (payload.tooltip && String(payload.tooltip).trim() !== "")
      root.updatesTooltip = String(payload.tooltip).trim()
    else if (root.hasUpdates)
      root.updatesTooltip = (root.text !== "" ? root.text : "New") + " updates"
    else
      root.updatesTooltip = "System up to date"
  }

  function recordCheck() {
    root.lastCheckedLabel = Qt.formatDateTime(new Date(), "hh:mm ap")
  }

  CommandRunner {
    id: availabilityRunner
    intervalMs: 0
    command: root.loginShell + " -lc 'command -v waybar-module-pacman-updates'"
    onRan: function(output) {
      root.moduleAvailable = output.trim() !== ""
    }
  }

  Process {
    id: updatesProcess
    command: ["sh", "-c", root.updatesCommand]
    running: root.moduleAvailable
    stdout: SplitParser {
      onRead: function(data) {
        root.updateFromPayloadText(data)
      }
    }
    Component.onCompleted: root.markNoUpdates()
  }

  content: [
    IconTextRow {
      spacing: root.contentSpacing
      iconText: root.hasUpdates ? root.updatesIcon : root.updatedIcon
      text: root.hasUpdates ? root.text : ""
    }
  ]

  MouseArea {
    anchors.fill: parent
    onClicked: Quickshell.execDetached(["sh", "-c", root.onClickCommand])
  }
}
