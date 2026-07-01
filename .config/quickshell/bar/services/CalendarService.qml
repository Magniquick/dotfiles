pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import qsnative
import "../../common/JsonUtils.js" as JsonUtils

Item {
  id: root
  visible: false

  property int days: 180

  property string status: ""
  property string generatedAt: ""
  property string error: ""
  property var eventsByDay: ({})
  property bool refreshing: false

  function applyClientPayload() {
    const parsed = JsonUtils.parseObject(calendarClient.events_json || "")
    if (!parsed || typeof parsed !== "object") {
      root.status = "error"
      root.generatedAt = ""
      root.error = calendarClient.error || "Failed to parse calendar payload"
      root.eventsByDay = ({})
      root.refreshing = false
      return
    }

    root.status = parsed.status ? String(parsed.status) : ""
    root.generatedAt = parsed.generatedAt ? String(parsed.generatedAt) : ""
    root.error = parsed.error ? String(parsed.error) : (calendarClient.error || "")
    root.eventsByDay = (parsed.eventsByDay && typeof parsed.eventsByDay === "object") ? parsed.eventsByDay : ({})
    root.refreshing = false
  }

  function refresh(reason) {
    root.refreshing = true
    calendarClient.refresh(root.days)
  }

  IcalCache {
    id: calendarClient
  }

  Timer {
    interval: 3600000
    repeat: true
    running: true
    triggeredOnStart: true

    onTriggered: root.refresh("timer")
  }

  Connections {
    target: calendarClient

    function onErrorChanged() {
      if (calendarClient.error)
        root.error = calendarClient.error
      root.refreshing = false
    }
    function onEvents_jsonChanged() {
      root.applyClientPayload()
    }
  }
}
