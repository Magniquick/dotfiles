import QtQml
import ".."

QtObject {
    id: root
    property real motionScale: 1

    readonly property MotionDistance distance: MotionDistance {}
    readonly property MotionDuration duration: MotionDuration {
        motionScale: root.motionScale
    }
    readonly property MotionEasing easing: MotionEasing {}
}
