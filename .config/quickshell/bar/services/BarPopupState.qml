pragma Singleton
pragma ComponentBehavior: Bound
import QtQml
import QtQuick

QtObject {
  id: root

  property rect anchorRect: Qt.rect(0, 0, 1, 1)
  property bool autoScroll: true
  property var browserLink: ""
  property Component contentComponent: null
  property var contentItem: null
  property bool enabled: false
  property bool hoverable: true
  property int maximumHeight: 0
  property bool open: false
  property bool popupHovered: false
  property bool refreshing: false
  property bool showBrowserIcon: false
  property bool showRefreshIcon: false
  property bool showScrollIndicator: true
  property string subtitle: ""
  property var targetItem: null
  property bool targetHovered: false
  property var targetWindow: null
  property string title: ""
  property bool visualActive: false
  property var _targets: []

  function activeFor(item) {
    return root.targetItem === item && root.enabled && (root.open || root.visualActive)
  }

  function visualActiveFor(item) {
    return root.targetItem === item && root.enabled && root.visualActive
  }

  function registerTarget(item) {
    if (!item || root._targets.indexOf(item) !== -1)
      return
    const next = root._targets.slice(0)
    next.push(item)
    root._targets = next
  }

  function unregisterTarget(item) {
    const index = root._targets.indexOf(item)
    if (index === -1)
      return
    const next = root._targets.slice(0)
    next.splice(index, 1)
    root._targets = next
    if (root.targetItem === item)
      root.closeNow()
  }

  function requestTarget(item, window) {
    if (!item || !item.tooltipEnabled || !item.visible) {
      releaseTarget(item)
      return
    }

    closeTimer.stop()
    root.targetItem = item
    root.targetWindow = window || null
    root.contentComponent = item.effectiveTooltipContent
    root.enabled = !!item.tooltipEnabled
    root.hoverable = !!item.tooltipHoverable
    root.browserLink = item.tooltipBrowserLink
    root.refreshing = !!item.tooltipRefreshing
    root.showBrowserIcon = !!item.tooltipShowBrowserIcon
    root.showRefreshIcon = !!item.tooltipShowRefreshIcon || item.tooltipTitle === "Calendar"
    root.subtitle = item.tooltipSubtitle || ""
    root.title = item.tooltipTitle || ""
    root.targetHovered = true
    root.open = root.enabled && root.contentComponent !== null
  }

  function refreshFromTarget(item, window) {
    if (root.targetItem !== item)
      return
    requestTarget(item, window)
  }

  function releaseTarget(item) {
    if (item && root.targetItem !== item)
      return
    root.targetHovered = false
    scheduleClose()
  }

  function setPopupHovered(hovered) {
    root.popupHovered = !!hovered
    if (root.popupHovered) {
      closeTimer.stop()
      if (root.enabled && root.targetWindow && root.contentComponent)
        root.open = true
    } else {
      scheduleClose()
    }
  }

  function scheduleClose() {
    if (root.targetHovered || (root.hoverable && root.popupHovered))
      return
    closeTimer.restart()
  }

  function closeNow() {
    closeTimer.stop()
    root.open = false
    root.targetHovered = false
    root.popupHovered = false
  }

  function finishClose() {
    if (root.open)
      return
    root.targetItem = null
    root.targetWindow = null
    root.contentComponent = null
    root.contentItem = null
    root.enabled = false
    root.hoverable = true
    root.browserLink = ""
    root.refreshing = false
    root.showBrowserIcon = false
    root.showRefreshIcon = false
    root.subtitle = ""
    root.title = ""
    root.anchorRect = Qt.rect(0, 0, 1, 1)
  }

  function requestRefresh() {
    if (root.targetItem)
      root.targetItem.tooltipRefreshRequested()
  }

  function resolveWindowPoint(window, x, y) {
    let best = null
    let bestArea = Number.MAX_VALUE
    for (let i = 0; i < root._targets.length; i++) {
      const item = root._targets[i]
      if (!item || !item.visible || !item.tooltipEnabled)
        continue
      const itemWindow = item.QsWindow ? item.QsWindow.window : null
      if (itemWindow !== window)
        continue
      const rect = window.itemRect(item)
      if (x < rect.x || y < rect.y || x > rect.x + rect.width || y > rect.y + rect.height)
        continue
      const area = Math.max(1, rect.width * rect.height)
      if (area < bestArea) {
        best = item
        bestArea = area
      }
    }

    if (best) {
      requestTarget(best, window)
    } else if (root.targetWindow === window) {
      releaseTarget(null)
    }
  }

  function leaveWindow(window) {
    if (root.targetWindow === window)
      releaseTarget(null)
  }

  property Timer closeTimer: Timer {
    id: closeTimer

    interval: 110
    repeat: false
    onTriggered: {
      if (!root.targetHovered && !(root.hoverable && root.popupHovered))
        root.open = false
    }
  }
}
