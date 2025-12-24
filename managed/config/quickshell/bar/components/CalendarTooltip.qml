import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "./JsonUtils.js" as JsonUtils

Item {
  id: root
  property date currentDate: new Date()
  property bool active: false
  property string cacheDir: ""
  property string refreshCommand: ""
  readonly property string eventsPath: root.cacheDir !== ""
    ? root.cacheDir + "/events.json"
    : ""
  property var eventsByDay: ({})
  property var dayEvents: []
  property int selectedDay: today
  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

  readonly property int year: currentDate.getFullYear()
  readonly property int month: currentDate.getMonth()
  readonly property int today: currentDate.getDate()
  readonly property int daysInMonth: new Date(year, month + 1, 0).getDate()
  readonly property int startOffset: new Date(year, month, 1).getDay()
  readonly property var weekDays: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
  readonly property int rowCount: Math.ceil((daysInMonth + startOffset) / 7)
  readonly property int totalCells: Math.max(28, rowCount * 7)
  readonly property int dayCellSize: Config.type.bodyMedium.size + Config.space.md

  function dayKey(dayNumber) {
    if (!dayNumber || dayNumber < 1 || dayNumber > root.daysInMonth)
      return ""
    const monthValue = root.month + 1
    const monthText = monthValue < 10 ? "0" + monthValue : String(monthValue)
    const dayText = dayNumber < 10 ? "0" + dayNumber : String(dayNumber)
    return root.year + "-" + monthText + "-" + dayText
  }

  function updateDayEvents() {
    const key = root.dayKey(root.selectedDay)
    const list = (key && root.eventsByDay && root.eventsByDay[key]) ? root.eventsByDay[key] : []
    root.dayEvents = list
  }

  function markerCount(dayNumber) {
    const key = root.dayKey(dayNumber)
    if (!key || !root.eventsByDay || !root.eventsByDay[key])
      return 0
    return Math.min(3, root.eventsByDay[key].length)
  }

  function formatEventTime(event) {
    if (!event || event.all_day)
      return "All day"
    const startValue = event.start ? new Date(event.start) : null
    if (!startValue || isNaN(startValue.getTime()))
      return ""
    return Qt.formatDateTime(startValue, "hh:mm ap")
  }

  function formatEventLabel(event) {
    if (!event)
      return ""
    const title = event.title && String(event.title).trim() !== "" ? event.title : "Untitled"
    const timeLabel = root.formatEventTime(event)
    return timeLabel !== "" ? timeLabel + " · " + title : title
  }

  function applyCalendarData(payload) {
    if (!payload || typeof payload !== "object") {
      root.eventsByDay = ({})
      root.updateDayEvents()
      return
    }
    root.eventsByDay = payload.eventsByDay ? payload.eventsByDay : ({})
    root.updateDayEvents()
  }

  CommandRunner {
    id: refreshRunner
    intervalMs: 3600000
    enabled: root.refreshCommand !== ""
    command: root.refreshCommand
    onRan: function() {
      if (root.active)
        eventsRunner.trigger()
    }
  }

  CommandRunner {
    id: eventsRunner
    intervalMs: 0
    enabled: root.active && root.eventsPath !== ""
    command: root.eventsPath !== "" ? "cat " + root.eventsPath : ""
    onRan: function(output) {
      root.applyCalendarData(JsonUtils.parseObject(output))
    }
  }

  onSelectedDayChanged: root.updateDayEvents()
  onEventsByDayChanged: root.updateDayEvents()
  onActiveChanged: {
    if (root.active)
      eventsRunner.trigger()
  }
  onCurrentDateChanged: {
    root.selectedDay = root.today
    root.updateDayEvents()
  }

  Component.onCompleted: {
    if (root.refreshCommand !== "")
      refreshRunner.trigger()
    root.updateDayEvents()
  }

  ColumnLayout {
    id: layout
    spacing: Config.space.sm

    Text {
      text: Qt.formatDateTime(root.currentDate, "yyyy MMMM")
      color: Config.textColor
      font.family: Config.fontFamily
      font.pixelSize: Config.type.titleMedium.size
      font.weight: Config.type.titleMedium.weight
      Layout.alignment: Qt.AlignHCenter
    }

    GridLayout {
      columns: 7
      columnSpacing: Config.space.sm
      rowSpacing: 0
      Layout.alignment: Qt.AlignHCenter

      Repeater {
        model: root.weekDays
        delegate: Item {
          implicitWidth: root.dayCellSize
          implicitHeight: Config.type.labelSmall.size + Config.space.xs

          Text {
            anchors.centerIn: parent
            text: modelData
            color: Config.textMuted
            font.family: Config.fontFamily
            font.pixelSize: Config.type.labelSmall.size
            font.weight: Config.type.labelSmall.weight
          }
        }
      }
    }

    GridLayout {
      columns: 7
      rowSpacing: Config.space.xs
      columnSpacing: Config.space.sm
      Layout.alignment: Qt.AlignHCenter

      Repeater {
        model: root.totalCells
        delegate: Item {
          readonly property int dayNumber: index - root.startOffset + 1
          readonly property bool inMonth: dayNumber > 0 && dayNumber <= root.daysInMonth
          readonly property bool isToday: inMonth && dayNumber === root.today
          readonly property bool isSelected: inMonth && dayNumber === root.selectedDay
          implicitWidth: root.dayCellSize
          implicitHeight: root.dayCellSize

          Rectangle {
            anchors.centerIn: parent
            width: parent.implicitWidth
            height: parent.implicitHeight
            radius: width / 2
            color: Config.color.secondary
            opacity: isToday ? 0.18 : 0
            visible: isToday
          }

          Rectangle {
            anchors.centerIn: parent
            width: parent.implicitWidth
            height: parent.implicitHeight
            radius: width / 2
            color: Config.moduleBackgroundHover
            opacity: isSelected && !isToday ? 0.4 : 0
            visible: isSelected && !isToday
          }

          Column {
            anchors.centerIn: parent
            spacing: 2

            Text {
              text: inMonth ? dayNumber : ""
              color: isToday ? Config.color.secondary : Config.textColor
              font.family: Config.fontFamily
              font.pixelSize: Config.type.bodyMedium.size
              font.weight: Config.type.bodyMedium.weight
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
            }

            Row {
              spacing: 2
              visible: inMonth && root.markerCount(dayNumber) > 0

              Repeater {
                model: root.markerCount(dayNumber)
                delegate: Rectangle {
                  width: 4
                  height: 4
                  radius: 2
                  color: Config.accent
                }
              }
            }
          }

          MouseArea {
            anchors.fill: parent
            enabled: inMonth
            onClicked: root.selectedDay = dayNumber
          }
        }
      }
    }

    ColumnLayout {
      spacing: Config.space.xs
      Layout.fillWidth: true

      Repeater {
        model: root.dayEvents && root.dayEvents.length > 0 ? root.dayEvents.slice(0, 4) : []
        delegate: Text {
          text: root.formatEventLabel(modelData)
          color: Config.textColor
          font.family: Config.fontFamily
          font.pixelSize: Config.type.bodySmall.size
          font.weight: Config.type.bodySmall.weight
          Layout.fillWidth: true
          elide: Text.ElideRight
        }
      }

      Text {
        text: "No events"
        color: Config.textMuted
        font.family: Config.fontFamily
        font.pixelSize: Config.type.bodySmall.size
        visible: !root.dayEvents || root.dayEvents.length === 0
      }
    }
  }
}
