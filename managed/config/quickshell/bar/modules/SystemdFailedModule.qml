import QtQuick
import Quickshell.Io
import ".."
import "../components"

ModuleContainer {
  id: root
  property int systemFailedCount: 0
  property int userFailedCount: 0
  property int failedCount: root.systemFailedCount + root.userFailedCount
  property bool enableEventRefresh: true
  property int eventDebounceMs: 750
  property bool debugLogging: false
  property bool systemPropsSignalPending: false
  property bool userPropsSignalPending: false
  tooltipText: root.failedCount > 0
    ? "Failed units: " + root.failedCount + " (system: " + root.systemFailedCount + ", user: " + root.userFailedCount + ")"
    : "Failed units: none"
  collapsed: root.failedCount <= 0

  function logEvent(message) {
    if (!root.debugLogging)
      return
    console.log("SystemdFailedModule " + new Date().toISOString() + " " + message)
  }

  function parseFailedCount(text) {
    if (!text || text.trim() === "")
      return 0
    const lines = text.trim().split("\n").filter(line => line.trim() !== "")
    return lines.length
  }

  function refreshCounts(source) {
    root.logEvent("refreshCounts " + source)
    systemRunner.trigger()
    userRunner.trigger()
  }

  function scheduleRefresh(source) {
    root.logEvent("scheduleRefresh " + source)
    if (!eventDebounce.running)
      eventDebounce.start()
  }

  function handleMonitorLine(source, data) {
    const trimmed = data.trim()
    if (trimmed === "")
      return
    if (trimmed.indexOf("signal ") === 0) {
      root.logEvent(source + "Monitor signal " + trimmed)
      root.scheduleRefresh(source)
    }
  }

  function handlePropsMonitorLine(source, data) {
    const trimmed = data.trim()
    if (trimmed === "")
      return
    if (trimmed.indexOf("signal ") === 0) {
      if (source === "system")
        root.systemPropsSignalPending = true
      else
        root.userPropsSignalPending = true
      root.logEvent(source + "Props signal " + trimmed)
      return
    }
    const pending = source === "system"
      ? root.systemPropsSignalPending
      : root.userPropsSignalPending
    if (!pending)
      return
    if (trimmed.indexOf("string \"NFailedUnits\"") !== -1 ||
        trimmed.indexOf("string \"FailedUnits\"") !== -1) {
      root.logEvent(source + "Props matched failed units")
      if (source === "system")
        root.systemPropsSignalPending = false
      else
        root.userPropsSignalPending = false
      root.scheduleRefresh(source + "-props")
    }
  }

  CommandRunner {
    id: systemRunner
    intervalMs: 0
    command: "systemctl --failed --no-legend --plain --no-pager"
    onOutputChanged: {
      root.systemFailedCount = root.parseFailedCount(output)
      root.logEvent("systemRunner output=" + root.systemFailedCount)
    }
  }

  CommandRunner {
    id: userRunner
    intervalMs: 0
    command: "systemctl --user --failed --no-legend --plain --no-pager"
    onOutputChanged: {
      root.userFailedCount = root.parseFailedCount(output)
      root.logEvent("userRunner output=" + root.userFailedCount)
    }
  }

  Process {
    id: systemMonitor
    command: [
      "dbus-monitor",
      "--system",
      "type='signal',sender='org.freedesktop.systemd1',interface='org.freedesktop.systemd1.Manager',member='JobRemoved'"
    ]
    running: root.enableEventRefresh
    stdout: SplitParser {
      onRead: function(data) {
        root.handleMonitorLine("system", data)
      }
    }
  }

  Process {
    id: systemPropsMonitor
    command: [
      "dbus-monitor",
      "--system",
      "type='signal',sender='org.freedesktop.systemd1',path='/org/freedesktop/systemd1',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.freedesktop.systemd1.Manager'"
    ]
    running: root.enableEventRefresh
    stdout: SplitParser {
      onRead: function(data) {
        root.handlePropsMonitorLine("system", data)
      }
    }
  }

  Process {
    id: userMonitor
    command: [
      "dbus-monitor",
      "--session",
      "type='signal',sender='org.freedesktop.systemd1',interface='org.freedesktop.systemd1.Manager',member='JobRemoved'"
    ]
    running: root.enableEventRefresh
    stdout: SplitParser {
      onRead: function(data) {
        root.handleMonitorLine("user", data)
      }
    }
  }

  Process {
    id: userPropsMonitor
    command: [
      "dbus-monitor",
      "--session",
      "type='signal',sender='org.freedesktop.systemd1',path='/org/freedesktop/systemd1',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.freedesktop.systemd1.Manager'"
    ]
    running: root.enableEventRefresh
    stdout: SplitParser {
      onRead: function(data) {
        root.handlePropsMonitorLine("user", data)
      }
    }
  }

  Timer {
    id: eventDebounce
    interval: root.eventDebounceMs
    repeat: false
    onTriggered: {
      root.logEvent("eventDebounce fired")
      root.refreshCounts("debounce")
    }
  }

  content: [
    IconTextRow {
      spacing: root.contentSpacing
      iconText: ""
      iconColor: Config.red
      text: root.failedCount + " units failed"
      textColor: Config.red
    }
  ]

  Component.onCompleted: root.refreshCounts("startup")
}
