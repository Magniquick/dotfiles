import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../components/JsonUtils.js" as JsonUtils

ModuleContainer {
  id: root
  property string iconText: ""
  property string cachedIconText: iconText
  property string cachedTooltip: ""
  property int tasksTooltipWidth: 320
  property string lastCheckedLabel: ""
  readonly property bool tasksRunning: tasksRunner.running
  readonly property string tasksCommand: root.loginShell + " -lc '" +
    Quickshell.shellPath("waybar/scripts/status.sh") + "'"
  readonly property string loginShell: {
    const shellValue = Quickshell.env("SHELL")
    return shellValue && shellValue !== "" ? shellValue : "sh"
  }
  property string onClickCommand: "quickshell -c powermenu ipc call powermenu toggle"
  tooltipHoverable: true
  tooltipContent: Component {
    TooltipCard {
      content: [
        Text {
          text: root.cachedTooltip !== "" ? root.cachedTooltip
            : (root.tasksRunning ? "Loading tasks..." : "Powermenu")
          color: Config.textColor
          font.family: Config.fontFamily
          font.pixelSize: Config.fontSize
          wrapMode: Text.Wrap
          textFormat: Text.RichText
          Layout.preferredWidth: root.tasksTooltipWidth
          Layout.maximumWidth: root.tasksTooltipWidth
        },
        InfoRow {
          label: "Last check"
          value: root.lastCheckedLabel !== "" ? root.lastCheckedLabel : "—"
        }
      ]
    }
  }

  function updateTasks(payloadText) {
    if (!payloadText)
      return
    const payload = JsonUtils.parseObject(payloadText)
    if (!payload) {
      root.cachedTooltip = JsonUtils.formatTooltip(payloadText)
      return
    }
    if (payload.text && payload.text.trim() !== "")
      root.cachedIconText = payload.text.trim()
    if (payload.tooltip && payload.tooltip.trim() !== "")
      root.cachedTooltip = JsonUtils.formatTooltip(payload.tooltip)
    root.iconText = root.cachedIconText
  }

  function recordCheck() {
    root.lastCheckedLabel = Qt.formatDateTime(new Date(), "hh:mm ap")
  }

  CommandRunner {
    id: tasksRunner
    intervalMs: 60000
    enabled: root.tooltipActive
    command: root.tasksCommand
    onRan: function(output) {
      root.recordCheck()
      root.updateTasks(output)
    }
    onEnabledChanged: {
      if (enabled)
        trigger()
    }
  }

  content: [
    IconLabel { text: root.iconText; color: Config.lavender }
  ]

  MouseArea {
    anchors.fill: parent
    onClicked: Quickshell.execDetached(["sh", "-c", root.onClickCommand])
  }

  onTooltipActiveChanged: {}
}
