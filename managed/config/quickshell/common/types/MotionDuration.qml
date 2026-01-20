import QtQml

QtObject {
  property real motionScale: 1

  readonly property int shortMs: Math.round(140 * motionScale)
  readonly property int medium: Math.round(180 * motionScale)
  readonly property int longMs: Math.round(240 * motionScale)
  readonly property int extraLong: Math.round(360 * motionScale)
  readonly property int pulse: Math.round(900 * motionScale)
}
