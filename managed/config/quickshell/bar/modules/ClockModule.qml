/**
 * @module ClockModule
 * @description Time and Google Calendar module
 *
 * Features:
 * - Time display (hh:mm ap format)
 * - Date display toggle on click
 * - Calendar tooltip with event integration
 * - Google Calendar cache for calendar events
 *
 * Dependencies:
 * - Google OAuth client/token secrets for configured calendar accounts
 */
pragma ComponentBehavior: Bound
import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell

ModuleContainer {
  id: root

  property string calendarRefreshTime: ""
  readonly property bool refreshing: CalendarService.refreshing
  property bool showDate: false

  function dateText() {
    return Qt.formatDateTime(clock.date, "dd/MM/yy")
  }
  function timeText() {
    return Qt.formatDateTime(clock.date, "hh:mm ap")
  }
  Component.onCompleted: {
    root.updateCalendarRefreshTime()
  }
  function updateCalendarRefreshTime() {
    const generatedAt = CalendarService.generatedAt
    if (generatedAt && String(generatedAt).trim() !== "") {
      const dt = new Date(generatedAt)
      root.calendarRefreshTime = Qt.formatDateTime(dt, "hh:mm ap")
      return
    }
    root.calendarRefreshTime = ""
  }

  tooltipHoverable: true
  tooltipRefreshing: root.refreshing
  tooltipSubtitle: calendarRefreshTime
  tooltipTitle: ""

  content: [
    BarLabel {
      color: Config.color.tertiary
      text: root.showDate ? root.dateText() : root.timeText()
    }
  ]
  tooltipContent: Component {
    ColumnLayout {
      spacing: Config.space.sm

      TooltipCard {
        backgroundColor: "transparent"
        outlined: false

        content: [
          CalendarTooltip {
            id: calendarRef

            active: root.tooltipActive
            currentDate: clock.date

            // Handle refresh signal from parent
            Connections {
              function onTooltipRefreshRequested() {
                calendarRef.refreshRequested()
              }

              target: root
            }
          }
        ]
      }
    }
  }

  onTooltipActiveChanged: {
    if (tooltipActive) {
      CalendarService.refresh("tooltip")
      root.updateCalendarRefreshTime()
    }
  }
  Connections {
    target: CalendarService

    function onGeneratedAtChanged() {
      root.updateCalendarRefreshTime()
    }
  }
  SystemClock {
    id: clock

    precision: SystemClock.Minutes
  }

  onClicked: root.showDate = !root.showDate
}
