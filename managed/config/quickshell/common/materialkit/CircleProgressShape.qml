import QtQuick

ShaderEffect {
  id: root

  property real progress: 0
  property bool animatedProgressEnabled: false
  property real animatedProgressFrom: 0
  property int animatedProgressDuration: 0
  property int animatedProgressKey: 0
  property real arcRadius: Math.max(0, Math.min(width, height) / 2 - strokeWidth)
  property real strokeWidth: 2
  property color strokeColor: "#ffffff"
  property color strokeColorValue: strokeColor
  property int capStyle: 32
  property vector2d itemSize: Qt.vector2d(width, height)
  property real renderProgress: 0

  readonly property real clampedProgress: Math.max(0, Math.min(1, Number(progress) || 0))
  readonly property real clampedAnimatedProgressFrom: Math.max(0, Math.min(1, Number(animatedProgressFrom) || 0))
  readonly property real clampedArcRadius: Math.max(0, Number(arcRadius) || 0)
  readonly property real clampedStrokeWidth: Math.max(0, Number(strokeWidth) || 0)

  blending: true
  fragmentShader: Qt.resolvedUrl("shaders/circle-progress.frag.qsb")
  mesh: Qt.size(1, 1)
  visible: renderProgress > 0 && clampedStrokeWidth > 0 && width > 0 && height > 0

  UniformAnimator on renderProgress {
    id: progressAnimator
    from: root.clampedAnimatedProgressFrom
    to: 1
    duration: Math.max(0, root.animatedProgressDuration)
    running: false
  }

  function syncStaticProgress() {
    if (animatedProgressEnabled)
      return
    progressAnimator.stop()
    renderProgress = clampedProgress
  }

  function restartAnimatedProgress() {
    if (!animatedProgressEnabled)
      return
    progressAnimator.stop()
    renderProgress = clampedAnimatedProgressFrom

    if (animatedProgressDuration <= 0 || clampedAnimatedProgressFrom >= 1) {
      renderProgress = clampedAnimatedProgressFrom
      return
    }

    progressAnimator.restart()
  }

  onProgressChanged: syncStaticProgress()
  onAnimatedProgressEnabledChanged: {
    if (animatedProgressEnabled)
      restartAnimatedProgress()
    else
      syncStaticProgress()
  }
  onAnimatedProgressFromChanged: {
    if (animatedProgressEnabled)
      restartAnimatedProgress()
  }
  onAnimatedProgressDurationChanged: {
    if (animatedProgressEnabled)
      restartAnimatedProgress()
  }
  onAnimatedProgressKeyChanged: restartAnimatedProgress()

  Component.onCompleted: {
    if (animatedProgressEnabled)
      restartAnimatedProgress()
    else
      syncStaticProgress()
  }
}
