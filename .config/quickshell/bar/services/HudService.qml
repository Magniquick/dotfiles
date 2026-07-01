pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Pipewire
import qsnative
import ".."

Item {
  id: root

  visible: false

  readonly property var settings: Config.systemHud
  property bool active: false
  property string currentKind: ""
  property string icon: ""
  property string label: ""
  property bool muted: false
  property int serial: 0
  property bool showProgress: true
  property int value: 0

  property var sink: Pipewire.defaultAudioSink
  property var sinkAudio: root.sink ? root.sink.audio : null
  property bool _audioPrimed: false
  property bool _audioMuted: false
  property int _audioValue: -1
  property bool _brightnessPrimed: false
  property int _brightnessValue: -1

  function averageVolume(values) {
    let total = 0
    for (let i = 0; i < values.length; i++)
      total += values[i]
    return values.length > 0 ? total / values.length : NaN
  }

  function resolveAudioValue() {
    if (!root.sink || !root.sink.ready || !root.sinkAudio)
      return NaN
    const values = root.sinkAudio.volumes
    if (values && values.length > 0)
      return root.averageVolume(values)
    return root.sinkAudio.volume
  }

  function audioIcon(percent, muted) {
    if (muted || percent <= 0)
      return ""
    if (percent < 34)
      return ""
    if (percent < 67)
      return ""
    return percent > 100 ? "󰝟" : ""
  }

  function brightnessIcon(percent) {
    const icons = ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "󰃚"]
    const index = Math.max(0, Math.min(icons.length - 1, Math.floor(percent / (100 / icons.length))))
    return icons[index]
  }

  function show(kind, iconValue, labelValue, percentValue, mutedValue, progressVisible) {
    if (!root.settings.enabled)
      return
    root.currentKind = kind
    root.icon = iconValue
    root.label = labelValue
    root.value = Math.max(0, Math.min(100, percentValue))
    root.muted = mutedValue
    root.showProgress = progressVisible
    root.active = true
    root.serial = root.serial + 1
    hideTimer.restart()
  }

  function hide() {
    root.active = false
    hideTimer.stop()
  }

  function refreshSink(primeOnly) {
    root.sink = Pipewire.defaultAudioSink
    root.sinkAudio = root.sink ? root.sink.audio : null
    root._audioPrimed = false
    root.syncAudio(!primeOnly)
  }

  function syncAudio(allowShow) {
    const volume = root.resolveAudioValue()
    if (!isFinite(volume))
      return
    const percent = Math.round(volume * 100)
    const nextMuted = !!(root.sinkAudio && root.sinkAudio.muted)

    if (!root._audioPrimed) {
      root._audioPrimed = true
      root._audioValue = percent
      root._audioMuted = nextMuted
      return
    }
    if (percent === root._audioValue && nextMuted === root._audioMuted)
      return

    root._audioValue = percent
    root._audioMuted = nextMuted
    if (allowShow)
      root.showAudioOutput(percent, nextMuted)
  }

  function showAudioOutput(percent, isMuted) {
    const clamped = Math.max(0, Math.min(200, percent))
    const text = isMuted ? qsTr("Muted") : (clamped + "%")
    root.show("audio_out", root.audioIcon(clamped, isMuted), text, Math.min(100, clamped), isMuted, true)
  }

  function syncBrightness(allowShow) {
    const backlight = BrightnessService.backlight
    if (!backlight || !backlight.available)
      return
    const percent = Math.max(0, Math.min(100, backlight.brightness_percent))

    if (!root._brightnessPrimed) {
      root._brightnessPrimed = true
      root._brightnessValue = percent
      return
    }
    if (percent === root._brightnessValue)
      return

    root._brightnessValue = percent
    if (allowShow)
      root.showBrightness(percent)
  }

  function showBrightness(percent) {
    root.show("backlight", root.brightnessIcon(percent), percent + "%", percent, false, true)
  }

  function showKeyboardLock(keyName) {
    if (keyName === "caps") {
      const stateText = keyboardLockProvider.caps_lock ? qsTr("On") : qsTr("Off")
      root.show("keyboard", "", qsTr("Caps Lock %1").arg(stateText), keyboardLockProvider.caps_lock ? 100 : 0, false, false)
    } else if (keyName === "num") {
      const stateText = keyboardLockProvider.num_lock ? qsTr("On") : qsTr("Off")
      root.show("keyboard", "", qsTr("Num Lock %1").arg(stateText), keyboardLockProvider.num_lock ? 100 : 0, false, false)
    }
  }

  Component.onCompleted: {
    root.refreshSink(true)
    root.syncBrightness(false)
    keyboardLockProvider.start(root.settings.keyboardPath)
  }

  Component.onDestruction: keyboardLockProvider.stop()

  Timer {
    id: hideTimer

    interval: root.settings.timeoutMs
    repeat: false
    onTriggered: root.active = false
  }

  KeyboardLockProvider {
    id: keyboardLockProvider
  }

  Connections {
    target: Pipewire

    function onDefaultAudioSinkChanged() {
      root.refreshSink(true)
    }

    function onReadyChanged() {
      root.refreshSink(true)
    }
  }

  Connections {
    target: root.sink

    function onReadyChanged() {
      root.syncAudio(false)
    }
  }

  Connections {
    target: root.sinkAudio

    function onMutedChanged() {
      root.syncAudio(true)
    }

    function onVolumesChanged() {
      root.syncAudio(true)
    }
  }

  Connections {
    target: BrightnessService.backlight

    function onAvailableChanged() {
      root._brightnessPrimed = false
      root.syncBrightness(false)
    }

    function onBrightness_percentChanged() {
      root.syncBrightness(true)
    }
  }

  Connections {
    target: keyboardLockProvider

    function onEvent_serialChanged() {
      root.showKeyboardLock(keyboardLockProvider.changed_key)
    }
  }
}
