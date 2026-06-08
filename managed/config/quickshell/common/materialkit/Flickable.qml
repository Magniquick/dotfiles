import QtQuick
import QtQuick.Controls
import "ScrollConstants.js" as Scroll

Flickable {
  id: flickable

  property alias verticalScrollBar: vbar
  property bool showVerticalScrollBar: true
  property bool autoHideVerticalScrollBar: true
  property int verticalScrollBarHideDelay: 900
  property real mouseWheelSpeed: Scroll.mouseWheelSpeed
  property real momentumVelocity: 0
  property bool isMomentumActive: false
  property real friction: Scroll.friction

  function showScrollBar() {
    if (flickable.showVerticalScrollBar)
      vbar.policy = ScrollBar.AsNeeded
  }

  function hideScrollBar() {
    if (flickable.autoHideVerticalScrollBar)
      vbar.policy = ScrollBar.AlwaysOff
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

  WheelHandler {
    id: wheelHandler

    property real touchpadSpeed: Scroll.touchpadSpeed
    property real momentumRetention: Scroll.momentumRetention
    property real lastWheelTime: 0
    property real momentum: 0
    property var velocitySamples: []
    property bool sessionUsedMouseWheel: false

    function startMomentum() {
      flickable.isMomentumActive = true
      momentumAnim.running = true
    }

    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

    onWheel: event => {
      const maxY = Math.max(0, flickable.contentHeight - flickable.height)
      if (maxY <= 0 || !flickable.interactive) {
        event.accepted = false
        return
      }

      flickable.showScrollBar()
      if (flickable.autoHideVerticalScrollBar)
        hideBarTimer.restart()

      const currentTime = Date.now()
      const timeDelta = currentTime - lastWheelTime
      lastWheelTime = currentTime

      const hasPixel = event.pixelDelta && event.pixelDelta.y !== 0
      const deltaY = event.angleDelta.y
      const isTraditionalMouse = !hasPixel && Math.abs(deltaY) >= 120 && (Math.abs(deltaY) % 120) === 0
      const isHighDpiMouse = !hasPixel && !isTraditionalMouse && deltaY !== 0
      const isTouchpad = hasPixel

      if (isTraditionalMouse) {
        sessionUsedMouseWheel = true
        momentumAnim.running = false
        flickable.isMomentumActive = false
        velocitySamples = []
        momentum = 0
        flickable.momentumVelocity = 0

        const lines = Math.round(Math.abs(deltaY) / 120)
        const scrollAmount = (deltaY > 0 ? -lines : lines) * flickable.mouseWheelSpeed
        flickable.contentY = Math.max(0, Math.min(maxY, flickable.contentY + scrollAmount))

        if (flickable.flicking)
          flickable.cancelFlick()
      } else if (isHighDpiMouse) {
        sessionUsedMouseWheel = true
        momentumAnim.running = false
        flickable.isMomentumActive = false
        velocitySamples = []
        momentum = 0
        flickable.momentumVelocity = 0

        const delta = deltaY / 8 * touchpadSpeed
        flickable.contentY = Math.max(0, Math.min(maxY, flickable.contentY - delta))

        if (flickable.flicking)
          flickable.cancelFlick()
      } else if (isTouchpad) {
        sessionUsedMouseWheel = false
        momentumAnim.running = false
        flickable.isMomentumActive = false

        let delta = event.pixelDelta.y * touchpadSpeed

        velocitySamples.push({
          "delta": delta,
          "time": currentTime
        })
        velocitySamples = velocitySamples.filter(sample => currentTime - sample.time < Scroll.velocitySampleWindowMs)

        if (velocitySamples.length > 1) {
          const totalDelta = velocitySamples.reduce((sum, sample) => sum + sample.delta, 0)
          const timeSpan = currentTime - velocitySamples[0].time
          if (timeSpan > 0) {
            flickable.momentumVelocity = Math.max(-Scroll.maxMomentumVelocity, Math.min(Scroll.maxMomentumVelocity, totalDelta / timeSpan * 1000))
          }
        }

        if (timeDelta < Scroll.momentumTimeThreshold) {
          momentum = momentum * momentumRetention + delta * Scroll.momentumDeltaFactor
          delta += momentum
        } else {
          momentum = 0
        }

        flickable.contentY = Math.max(0, Math.min(maxY, flickable.contentY - delta))

        if (flickable.flicking)
          flickable.cancelFlick()
      }

      event.accepted = true
    }

    onActiveChanged: {
      if (!active) {
        if (!sessionUsedMouseWheel && Math.abs(flickable.momentumVelocity) >= Scroll.minMomentumVelocity) {
          startMomentum()
        } else {
          velocitySamples = []
          flickable.momentumVelocity = 0
        }
      }
    }
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

  FrameAnimation {
    id: momentumAnim
    running: false

    onTriggered: {
      const dt = frameTime
      const maxY = Math.max(0, flickable.contentHeight - flickable.height)
      const newY = flickable.contentY - flickable.momentumVelocity * dt

      if (newY < 0 || newY > maxY) {
        flickable.contentY = newY < 0 ? 0 : maxY
        running = false
        flickable.isMomentumActive = false
        flickable.momentumVelocity = 0
        if (flickable.autoHideVerticalScrollBar)
          hideBarTimer.restart()
        return
      }

      flickable.contentY = newY
      flickable.momentumVelocity *= Math.pow(flickable.friction, dt / 0.016)

      if (Math.abs(flickable.momentumVelocity) < Scroll.momentumStopThreshold) {
        running = false
        flickable.isMomentumActive = false
        flickable.momentumVelocity = 0
        if (flickable.autoHideVerticalScrollBar)
          hideBarTimer.restart()
      }
    }
  }

  Timer {
    id: hideBarTimer
    interval: flickable.verticalScrollBarHideDelay
    onTriggered: flickable.hideScrollBar()
  }

  ScrollBar.vertical: ScrollBar {
    id: vbar
    policy: flickable.showVerticalScrollBar ? (flickable.autoHideVerticalScrollBar ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded) : ScrollBar.AlwaysOff
  }
}
