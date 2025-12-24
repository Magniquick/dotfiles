import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../components"
import "../components/JsonUtils.js" as JsonUtils

ModuleContainer {
  id: root
  property string iconText: "󱅫"
  property string statusAlt: "notification"
  property string statusTooltip: "Notifications"
  property color iconColor: Config.accent
  property var iconMap: ({
    "notification": "󱅫",
    "none": "",
    "dnd-notification": "󰂠",
    "dnd-none": "󰪓",
    "inhibited-notification": "󰂛",
    "inhibited-none": "󰪑",
    "dnd-inhibited-notification": "󰂛",
    "dnd-inhibited-none": "󰪑"
  })
  property string onClickCommand: "swaync-client -t -sw"
  property string onRightClickCommand: "swaync-client -d -sw"
  tooltipTitle: "Notifications"
  tooltipText: root.statusTooltip
  tooltipContent: Component {
    ColumnLayout {
      spacing: Config.space.sm

      TooltipCard {
        content: [
          Text {
            text: root.statusTooltip
            color: Config.textColor
            font.family: Config.fontFamily
            font.pixelSize: Config.fontSize
            wrapMode: Text.Wrap
            Layout.preferredWidth: 260
            Layout.maximumWidth: 320
          }
        ]
      }

      TooltipActionsRow {
        ActionChip {
          text: "Open"
          onClicked: Quickshell.execDetached(["sh", "-c", root.onClickCommand])
        }

        ActionChip {
          text: root.isDndActive() ? "DND On" : "DND Off"
          active: root.isDndActive()
          onClicked: Quickshell.execDetached(["sh", "-c", root.onRightClickCommand])
        }
      }
    }
  }

  function updateFromPayload(payload) {
    if (!payload)
      return
    const alt = payload.alt || payload.class || ""
    if (alt)
      root.statusAlt = alt
    const icon = root.iconMap[root.statusAlt] || root.iconMap.notification
    root.iconText = icon
    if (payload.tooltip && payload.tooltip !== "")
      root.statusTooltip = payload.tooltip
    else
      root.statusTooltip = "Notifications"
  }

  function isDndActive() {
    return root.statusAlt.indexOf("dnd") >= 0 || root.statusAlt.indexOf("inhibited") >= 0
  }

  Process {
    id: watchProcess
    command: ["swaync-client", "-swb"]
    running: true
    stdout: SplitParser {
      onRead: function(data) {
        const line = data.trim()
        if (!line)
          return
        const payload = JsonUtils.parseObject(line)
        if (payload)
          root.updateFromPayload(payload)
      }
    }
  }

  content: [
    IconLabel {
      text: root.iconText
      color: root.iconColor
      font.pixelSize: Config.iconSize + 2
    }
  ]

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: {
      if (mouse.button === Qt.RightButton)
        Quickshell.execDetached(["sh", "-c", root.onRightClickCommand])
      else
        Quickshell.execDetached(["sh", "-c", root.onClickCommand])
    }
  }
}
