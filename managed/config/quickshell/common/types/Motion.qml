import QtQml
import ".."

QtObject {
  property real motionScale: 1

  readonly property MotionDistance distance: MotionDistance {}
  readonly property MotionDuration duration: MotionDuration {
    motionScale: root.motionScale
  }
  readonly property MotionEasing easing: MotionEasing {}

  id: root
}
