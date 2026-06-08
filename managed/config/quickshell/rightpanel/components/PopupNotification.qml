import QtQuick
import "../../common" as Common

Item {
  id: root
  property var entry
  signal dismissRequested

  property int dismissTotalMs: 0
  readonly property bool autoDismissEnabled: root.entry && root.entry.timer && root.entry.timer.interval > 0
  property bool autoDismissPaused: false
  property double dismissElapsedMs: 0
  property double dismissStartedAtMs: 0
  property bool _entered: false
  readonly property real exitOffsetX: width + (2 * Common.Config.space.sm)

  width: 320
  x: ((root.entry && root.entry.popupExiting) || !root._entered) ? root.exitOffsetX : 0
  implicitHeight: frame.implicitHeight
  // ListView positions delegates using `height`; bind it so late implicitHeight
  // changes (e.g. async image checks / text wrap) trigger relayout instead of
  // overlapping the previous item.
  height: implicitHeight

  Behavior on x {
    XAnimator {
      duration: Common.Config.motion.duration.shortMs
      easing.type: Common.Config.motion.easing.standard
    }
  }

  Component.onCompleted: {
    root._entered = true
    resetAutoDismiss()
  }

  HoverHandler {
    id: cardHover

    onHoveredChanged: {
      if (cardHover.hovered)
        root.pauseAutoDismiss()
      else
        root.resumeAutoDismiss()
    }
  }

  function resetAutoDismiss() {
    dismissTotalMs = autoDismissEnabled ? root.entry.timer.interval : 0
    autoDismissPaused = false
    dismissElapsedMs = 0
    dismissStartedAtMs = 0
    root.stopAutoDismissLine(autoDismissEnabled ? 1.0 : 0.0)

    if (!autoDismissEnabled)
      return
    if (cardHover.hovered) {
      autoDismissPaused = true
      root.entry.timer.stop()
      return
    }

    dismissStartedAtMs = Date.now()
    root.startAutoDismissLine(dismissTotalMs, 1.0)
  }

  function pauseAutoDismiss() {
    if (!autoDismissEnabled)
      return
    if (autoDismissPaused)
      return
    autoDismissPaused = true
    root.captureElapsedProgress()
    root.entry.timer.stop()
    root.stopAutoDismissLine(root.remainingDismissProgress())
  }

  function resumeAutoDismiss() {
    if (!autoDismissEnabled)
      return
    if (!autoDismissPaused)
      return
    autoDismissPaused = false

    const remainingMs = dismissTotalMs - dismissElapsedMs
    if (remainingMs <= 0) {
      // Let the existing timeout path remove the popup.
      root.entry.timer.interval = 1
      root.entry.timer.restart()
      return
    }

    root.entry.timer.interval = remainingMs
    root.entry.timer.restart()
    root.startAutoDismissLine(remainingMs, root.remainingDismissProgress())
    dismissStartedAtMs = Date.now()
  }

  function captureElapsedProgress() {
    if (dismissTotalMs <= 0)
      return
    if (dismissStartedAtMs > 0)
      dismissElapsedMs += Math.max(0, Date.now() - dismissStartedAtMs)

    dismissElapsedMs = Math.max(0, Math.min(dismissTotalMs, dismissElapsedMs))
    dismissStartedAtMs = 0
  }

  function remainingDismissProgress() {
    if (dismissTotalMs <= 0)
      return 0
    return Math.max(0, Math.min(1, 1 - (dismissElapsedMs / dismissTotalMs)))
  }

  function stopAutoDismissLine(scaleValue) {
    const clampedScale = Math.max(0, Math.min(1, Number(scaleValue) || 0))
    autoDismissLineAnimator.stop()
    autoDismissLine.scale = clampedScale
  }

  function startAutoDismissLine(durationMs, fromScale) {
    const clampedScale = Math.max(0, Math.min(1, Number(fromScale) || 0))
    const clampedDuration = Math.max(0, Math.round(Number(durationMs) || 0))
    autoDismissLineAnimator.stop()
    autoDismissLine.scale = clampedScale
    autoDismissLineAnimator.from = clampedScale
    autoDismissLineAnimator.duration = clampedDuration

    if (clampedDuration <= 0 || clampedScale <= 0)
      return
    autoDismissLineAnimator.restart()
  }

  Connections {
    target: root.entry
    function onTimerChanged() {
      root.resetAutoDismiss()
    }
  }

  onEntryChanged: resetAutoDismiss()

  function activatePopup() {
    const notification = root.entry ? root.entry.notification : null
    const actions = notification && notification.actions ? notification.actions : []
    let invoked = false

    for (let i = 0; i < actions.length; i++) {
      const action = actions[i]
      const identifier = action && action.identifier ? String(action.identifier) : ""
      if (identifier === "default" && typeof action.invoke === "function") {
        action.invoke()
        invoked = true
        break
      }
    }

    // Match common notification UX: activate first, then close popup.
    // If no default action exists, this still dismisses as a fallback.
    root.dismissRequested()
    return invoked
  }

  NotificationFrame {
    id: frame
    anchors {
      left: parent.left
      right: parent.right
    }
    // Popups sit on an overlay layer; the drop shadow makes the container
    // edge harder to read against busy backgrounds.
    elevation: 0
    frameBorderWidth: 1
    frameBorderColor: Qt.alpha(Common.Config.color.outline, 0.42)
    onClicked: root.activatePopup()

    NotificationContent {
      id: content
      anchors {
        left: parent.left
        right: parent.right
        top: parent.top
      }
      entry: root.entry
      showCloseButton: true
      bodyMaxLines: 3
      bodyExpandable: true
      bodyExpandOnHover: true
      bodyHoverActive: cardHover.hovered
      bodyHoverMaxLines: 15
      bodyHyphenate: true
      onCloseClicked: root.dismissRequested()
    }
  }

  Rectangle {
    id: autoDismissLine

    anchors {
      left: frame.left
      right: frame.right
      bottom: frame.bottom
      leftMargin: frame.frameRadius
      rightMargin: frame.frameRadius
      bottomMargin: frame.frameBorderWidth + 1
    }
    height: 2
    radius: height / 2
    color: Common.Config.color.primary
    opacity: root.autoDismissPaused ? 0.45 : 0.85
    transformOrigin: Item.Left
    scale: 0
    visible: root.autoDismissEnabled
  }

  ScaleAnimator {
    id: autoDismissLineAnimator

    target: autoDismissLine
    from: 1
    to: 0
    duration: 0
    running: false
  }
}
