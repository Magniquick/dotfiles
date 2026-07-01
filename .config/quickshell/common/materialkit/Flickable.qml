import QtQuick
import QtQuick.Controls
import "ScrollConstants.js" as Scroll
import "../" as Common

Flickable {
  id: flickable

  property alias verticalScrollBar: vbar
  property bool showVerticalScrollBar: true
  property bool autoHideVerticalScrollBar: true
  property int verticalScrollBarHideDelay: 900
  property bool smoothTouchpadScroll: true
  property real smoothTouchpadScrollFactor: Scroll.smoothTouchpadScrollFactor
  property real smoothTouchpadAngleThreshold: Scroll.smoothTouchpadAngleThreshold
  property real scrollTargetY: 0
  property real smoothScrollDurationMs: Scroll.smoothTouchpadDurationMs
  property real touchpadMomentumVelocity: 0
  property real touchpadMomentumFrameVelocity: 0
  property real touchpadMomentumElapsedMs: 0
  property bool suppressContentYBehavior: false
  property var velocitySamples: []

  function showScrollBar() {
    if (flickable.showVerticalScrollBar)
      vbar.policy = ScrollBar.AsNeeded
  }

  function hideScrollBar() {
    if (flickable.autoHideVerticalScrollBar)
      vbar.policy = ScrollBar.AlwaysOff
  }

  function startTouchpadMomentum() {
    const currentTime = Date.now()
    const latestSample = flickable.velocitySamples.length > 0 ? flickable.velocitySamples[flickable.velocitySamples.length - 1] : null
    if (!latestSample || currentTime - latestSample.time > Scroll.momentumReleaseWindowMs) {
      flickable.touchpadMomentumVelocity = 0
      flickable.velocitySamples = []
      return
    }

    if (Math.abs(flickable.touchpadMomentumVelocity) < Scroll.minMomentumVelocity)
      return

    flickable.touchpadMomentumFrameVelocity = flickable.touchpadMomentumVelocity * Scroll.smoothTouchpadMomentumFrameScale
    flickable.touchpadMomentumElapsedMs = 0
    flickable.touchpadMomentumVelocity = 0
    flickable.velocitySamples = []
    momentumAnim.running = true
  }

  clip: true
  contentWidth: width
  interactive: contentHeight > height
  flickDeceleration: Scroll.flickDeceleration
  maximumFlickVelocity: Scroll.maximumFlickVelocity
  boundsBehavior: Flickable.StopAtBounds
  boundsMovement: Flickable.FollowBoundsBehavior
  pressDelay: 0
  flickableDirection: Flickable.VerticalFlick

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    enabled: flickable.smoothTouchpadScroll

    onWheel: wheel => {
      const hasHorizontalDelta = (wheel.pixelDelta && wheel.pixelDelta.x !== 0) || wheel.angleDelta.x !== 0
      if (hasHorizontalDelta || (wheel.modifiers & Qt.ShiftModifier)) {
        wheel.accepted = false
        return
      }

      const maxY = Math.max(0, flickable.contentHeight - flickable.height)
      if (maxY <= 0 || !flickable.interactive) {
        wheel.accepted = false
        return
      }

      const hasPixel = wheel.pixelDelta && wheel.pixelDelta.y !== 0
      const angleY = wheel.angleDelta.y
      const hasPhase = wheel.phase !== undefined && wheel.phase !== Qt.NoScrollPhase
      const isScrollEnd = hasPhase && wheel.phase === Qt.ScrollEnd
      const touchpadLike = hasPixel || (angleY !== 0 && Math.abs(angleY) < flickable.smoothTouchpadAngleThreshold)
      if (isScrollEnd) {
        flickable.startTouchpadMomentum()
        wheel.accepted = true
        return
      }

      if (!touchpadLike) {
        wheel.accepted = false
        return
      }

      momentumAnim.running = false
      flickable.touchpadMomentumFrameVelocity = 0
      flickable.smoothScrollDurationMs = Scroll.smoothTouchpadDurationMs
      flickable.showScrollBar()
      if (flickable.autoHideVerticalScrollBar)
        hideBarTimer.restart()

      const delta = hasPixel ? wheel.pixelDelta.y : angleY / flickable.smoothTouchpadAngleThreshold * flickable.smoothTouchpadScrollFactor
      const base = scrollAnim.running ? flickable.scrollTargetY : flickable.contentY
      const currentTime = Date.now()
      const contentDelta = -delta
      flickable.velocitySamples.push({
        "delta": contentDelta,
        "time": currentTime
      })
      flickable.velocitySamples = flickable.velocitySamples.filter(sample => currentTime - sample.time < Scroll.velocitySampleWindowMs)

      if (flickable.velocitySamples.length > 1) {
        const totalDelta = flickable.velocitySamples.reduce((sum, sample) => sum + sample.delta, 0)
        const timeSpan = currentTime - flickable.velocitySamples[0].time
        if (timeSpan > 0)
          flickable.touchpadMomentumVelocity = Math.max(-Scroll.maxMomentumVelocity, Math.min(Scroll.maxMomentumVelocity, totalDelta / timeSpan * 1000))
      }

      flickable.scrollTargetY = Math.max(0, Math.min(base - delta, maxY))
      flickable.suppressContentYBehavior = true
      flickable.contentY = flickable.scrollTargetY
      flickable.suppressContentYBehavior = false

      if (flickable.flicking)
        flickable.cancelFlick()

      if (hasPhase)
        touchpadMomentumTimer.stop()
      else
        touchpadMomentumTimer.restart()
      wheel.accepted = true
    }
  }

  Timer {
    id: touchpadMomentumTimer
    interval: Scroll.momentumTimeThreshold

    onTriggered: {
      flickable.startTouchpadMomentum()
    }
  }

  Behavior on contentY {
    enabled: !momentumAnim.running && !flickable.suppressContentYBehavior

    NumberAnimation {
      id: scrollAnim
      alwaysRunToEnd: true
      duration: flickable.smoothScrollDurationMs
      easing.type: Common.Config.motion.easing.standard
    }
  }

  onContentYChanged: {
    if (!scrollAnim.running)
      flickable.scrollTargetY = flickable.contentY
  }

  onMovementStarted: {
    flickable.showScrollBar()
    if (flickable.autoHideVerticalScrollBar)
      hideBarTimer.stop()
  }
  onMovementEnded: {
    if (flickable.autoHideVerticalScrollBar)
      hideBarTimer.restart()
  }

  Timer {
    id: hideBarTimer
    interval: flickable.verticalScrollBarHideDelay
    onTriggered: flickable.hideScrollBar()
  }

  FrameAnimation {
    id: momentumAnim
    running: false

    onTriggered: {
      const dt = frameTime
      flickable.touchpadMomentumElapsedMs += dt * 1000
      if (flickable.touchpadMomentumElapsedMs >= Scroll.maxMomentumDurationMs) {
        flickable.touchpadMomentumFrameVelocity = 0
        running = false
        return
      }

      const maxY = Math.max(0, flickable.contentHeight - flickable.height)
      const newY = flickable.contentY + flickable.touchpadMomentumFrameVelocity * dt

      if (newY < 0 || newY > maxY) {
        flickable.contentY = newY < 0 ? 0 : maxY
        flickable.scrollTargetY = flickable.contentY
        flickable.touchpadMomentumFrameVelocity = 0
        running = false
        return
      }

      flickable.contentY = newY
      flickable.scrollTargetY = newY
      flickable.touchpadMomentumFrameVelocity *= Math.pow(Scroll.friction, dt / 0.016)

      if (Math.abs(flickable.touchpadMomentumFrameVelocity) < Scroll.momentumStopThreshold) {
        flickable.touchpadMomentumFrameVelocity = 0
        running = false
      }
    }
  }

  ScrollBar.vertical: ScrollBar {
    id: vbar
    policy: flickable.showVerticalScrollBar ? (flickable.autoHideVerticalScrollBar ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded) : ScrollBar.AlwaysOff
  }
}
