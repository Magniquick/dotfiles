pragma Singleton

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qsgo

Singleton {
  id: root

  property bool debugLogging: false
  readonly property string lastRefreshedLabel: String(provider.last_checked || "")
  readonly property int systemFailedCount: provider.system_failed_count
  readonly property var systemFailedUnits: provider.system_failed_units
  readonly property int userFailedCount: provider.user_failed_count
  readonly property var userFailedUnits: provider.user_failed_units
  readonly property string error: String(provider.error || "")
  readonly property bool refreshing: provider.refreshing

  readonly property int failedCount: provider.failed_count

  function logEvent(message) {
    if (!root.debugLogging) {
      return
    }
    console.log("SystemdFailedService " + new Date().toISOString() + " " + message)
  }

  function refreshCounts(source) {
    root.logEvent("refreshCounts " + (source || "unknown"))
    provider.refresh()
  }

  Component.onCompleted: {
    provider.start()
  }

  SystemdFailedProvider {
    id: provider
  }

  Connections {
    target: provider

    function onFailed_countChanged() {
      root.logEvent("provider failed_count=" + provider.failed_count)
    }

    function onErrorChanged() {
      if (provider.error) {
        console.warn("SystemdFailedService provider error:", provider.error)
      }
    }
  }
}
