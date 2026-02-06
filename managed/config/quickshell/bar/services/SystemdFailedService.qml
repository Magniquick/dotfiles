pragma Singleton

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../components"

Singleton {
  id: root

  property bool debugLogging: false
  property bool enableEventRefresh: true
  property int eventDebounceMs: 750

  property string lastRefreshedLabel: ""
  property int systemFailedCount: 0
  property var systemFailedUnits: []
  property bool systemPropsSignalPending: false
  property int userFailedCount: 0
  property var userFailedUnits: []
  property bool userPropsSignalPending: false

  readonly property int failedCount: root.systemFailedCount + root.userFailedCount

  function logEvent(message) {
    if (!root.debugLogging) {
      return
    }
    console.log("SystemdFailedService " + new Date().toISOString() + " " + message)
  }

  function parseFailedUnits(text) {
    if (!text || text.trim() === "") {
      return []
    }

    const lines = text.trim().split("\n").map(line => {
      return line.trim()
    }).filter(line => {
      return line !== ""
    })

    const units = []
    for (let i = 0; i < lines.length; i++) {
      let line = lines[i]
      if (line.indexOf("0 loaded units listed") === 0) {
        continue
      }

      if (line.indexOf("UNIT ") === 0) {
        continue
      }

      line = line.replace(/^●\s+/, "")
      const parts = line.split(/\s+/)
      if (parts.length === 0) {
        continue
      }

      const unit = parts[0] || ""
      const load = parts[1] || ""
      const active = parts[2] || ""
      const sub = parts[3] || ""
      const description = parts.slice(4).join(" ")
      if (unit) {
        units.push({
          "unit": unit,
          "load": load,
          "active": active,
          "sub": sub,
          "description": description
        })
      }
    }
    return units
  }

  function refreshCounts(source) {
    root.logEvent("refreshCounts " + (source || "unknown"))
    systemRunner.trigger()
    userRunner.trigger()
  }

  function scheduleRefresh(source) {
    root.logEvent("scheduleRefresh " + source)
    if (!eventDebounce.running) {
      eventDebounce.start()
    }
  }

  function handleMonitorLine(source, data) {
    const trimmed = data.trim()
    if (trimmed === "") {
      return
    }

    if (trimmed.indexOf("signal ") === 0) {
      root.logEvent(source + "Monitor signal " + trimmed)
      root.scheduleRefresh(source)
    }
  }

  function handlePropsMonitorLine(source, data) {
    const trimmed = data.trim()
    if (trimmed === "") {
      return
    }

    if (trimmed.indexOf("signal ") === 0) {
      if (source === "system") {
        root.systemPropsSignalPending = true
      } else {
        root.userPropsSignalPending = true
      }
      root.logEvent(source + "Props signal " + trimmed)
      return
    }

    const pending = source === "system" ? root.systemPropsSignalPending : root.userPropsSignalPending
    if (!pending) {
      return
    }

    if (trimmed.indexOf("string \"NFailedUnits\"") !== -1 || trimmed.indexOf("string \"FailedUnits\"") !== -1) {
      root.logEvent(source + "Props matched failed units")
      if (source === "system") {
        root.systemPropsSignalPending = false
      } else {
        root.userPropsSignalPending = false
      }
      root.scheduleRefresh(source + "-props")
    }
  }

  Component.onCompleted: {
    root.refreshCounts("startup")
  }

  CommandRunner {
    id: systemRunner

    command: "systemctl --failed --no-legend --plain --no-pager"
    intervalMs: 0

    onOutputChanged: {
      root.systemFailedUnits = root.parseFailedUnits(output)
      root.systemFailedCount = root.systemFailedUnits.length
      root.lastRefreshedLabel = Qt.formatDateTime(new Date(), "hh:mm ap")
      root.logEvent("systemRunner output=" + root.systemFailedCount)
    }
  }

  CommandRunner {
    id: userRunner

    command: "systemctl --user --failed --no-legend --plain --no-pager"
    intervalMs: 0

    onOutputChanged: {
      root.userFailedUnits = root.parseFailedUnits(output)
      root.userFailedCount = root.userFailedUnits.length
      root.lastRefreshedLabel = Qt.formatDateTime(new Date(), "hh:mm ap")
      root.logEvent("userRunner output=" + root.userFailedCount)
    }
  }

  ProcessMonitor {
    id: systemMonitor

    command: ["dbus-monitor", "--system", "type='signal',sender='org.freedesktop.systemd1',interface='org.freedesktop.systemd1.Manager',member='JobRemoved'"]
    enabled: root.enableEventRefresh

    onOutput: data => root.handleMonitorLine("system", data)
  }

  ProcessMonitor {
    id: systemPropsMonitor

    command: ["dbus-monitor", "--system", "type='signal',sender='org.freedesktop.systemd1',path='/org/freedesktop/systemd1',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.freedesktop.systemd1.Manager'"]
    enabled: root.enableEventRefresh

    onOutput: data => root.handlePropsMonitorLine("system", data)
  }

  ProcessMonitor {
    id: userMonitor

    command: ["dbus-monitor", "--session", "type='signal',sender='org.freedesktop.systemd1',interface='org.freedesktop.systemd1.Manager',member='JobRemoved'"]
    enabled: root.enableEventRefresh

    onOutput: data => root.handleMonitorLine("user", data)
  }

  ProcessMonitor {
    id: userPropsMonitor

    command: ["dbus-monitor", "--session", "type='signal',sender='org.freedesktop.systemd1',path='/org/freedesktop/systemd1',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.freedesktop.systemd1.Manager'"]
    enabled: root.enableEventRefresh

    onOutput: data => root.handlePropsMonitorLine("user", data)
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
}
