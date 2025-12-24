import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"

ModuleContainer {
  id: root
  property bool showDate: false
  readonly property string loginShell: {
    const shellValue = Quickshell.env("SHELL")
    return shellValue && shellValue !== "" ? shellValue : "sh"
  }
  readonly property string calendarCacheDir: {
    const homeDir = Quickshell.env("HOME")
    return homeDir && homeDir !== "" ? homeDir + "/.cache/quickshell/ical" : "/tmp/quickshell-ical"
  }
  readonly property string calendarBinary: Quickshell.shellPath("scripts/ical-cache/target/release/ical-cache")
  readonly property string calendarEnvFile: Quickshell.shellPath(".env")
  readonly property string calendarRefreshCommand: root.loginShell + " -lc '" + root.calendarBinary +
    " --cache-dir " + root.calendarCacheDir + " --env-file " + root.calendarEnvFile + "'"
  tooltipTitle: "Calendar"
  tooltipHoverable: true
  tooltipContent: Component {
    ColumnLayout {
      spacing: Config.space.sm

      TooltipCard {
        content: [
          CalendarTooltip {
            currentDate: clock.date
            active: root.tooltipActive
            cacheDir: root.calendarCacheDir
            refreshCommand: root.calendarRefreshCommand
          }
        ]
      }

      TooltipActionsRow {
        ActionChip {
          text: root.showDate ? "Show time" : "Show date"
          onClicked: root.showDate = !root.showDate
        }
      }
    }
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  function timeText() {
    return Qt.formatDateTime(clock.date, "hh:mm ap")
  }

  function dateText() {
    return Qt.formatDateTime(clock.date, "dd/MM/yy")
  }

  content: [
    BarLabel {
      text: root.showDate ? root.dateText() : root.timeText()
      color: Config.lavender
    }
  ]

  MouseArea {
    anchors.fill: parent
    onClicked: root.showDate = !root.showDate
  }
}
