import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import ".."
import "../components"

ModuleContainer {
  id: root
  property var sink: Pipewire.defaultAudioSink
  property var sinkAudio: root.sink ? root.sink.audio : null
  readonly property bool pipewireReady: root.sink ? root.sink.ready : false
  property bool debugLogging: false
  property real sliderValue: 0
  property int volumePercent: 0
  property bool muted: false
  property bool volumeAvailable: false
  property real volumeStep: 0.01
  property real maxVolume: 2.0
  property var icons: ["", "", "", ""]
  property string mutedIcon: ""
  property string onScrollUpCommand: "wpctl set-volume -l 2 @DEFAULT_AUDIO_SINK@ 1%+"
  property string onScrollDownCommand: "wpctl set-volume -l 2 @DEFAULT_AUDIO_SINK@ 1%-"
  tooltipTitle: "Volume"
  tooltipHoverable: true
  tooltipText: root.volumeAvailable
    ? (root.muted ? "Volume: muted" : "Volume: " + root.volumePercent + "%")
    : "Volume: unavailable"
  tooltipContent: Component {
    ColumnLayout {
      spacing: Config.space.sm

      TooltipCard {
        content: [
          RowLayout {
            spacing: Config.space.sm

            IconLabel {
              text: root.iconForVolume()
              color: root.muted ? Config.red : Config.pink
              font.pixelSize: Config.iconSize + 4
            }

            Text {
              text: root.volumeAvailable
                ? (root.muted ? "Muted" : root.volumePercent + "%")
                : "Unavailable"
              color: Config.textColor
              font.family: Config.fontFamily
              font.pixelSize: Config.fontSize + 2
              Layout.fillWidth: true
            }
          },
          InfoRow {
            label: "Device"
            value: root.sinkLabel()
            visible: root.sinkLabel() !== ""
          },
          LevelSlider {
            Layout.fillWidth: true
            minimum: 0
            maximum: root.maxVolume
            value: root.sliderValue
            enabled: root.volumeAvailable
            fillColor: root.muted ? Config.red : Config.pink
            onUserChanged: {
              root.sliderValue = value
              root.setVolume(value)
            }
          }
        ]
      }

      TooltipActionsRow {
        ActionChip {
          text: root.muted ? "Unmute" : "Mute"
          active: root.muted
          onClicked: root.toggleMute()
        }

        ActionChip {
          text: "50%"
          onClicked: root.setVolume(0.5)
        }

        ActionChip {
          text: "100%"
          onClicked: root.setVolume(1.0)
        }

        ActionChip {
          text: "150%"
          onClicked: root.setVolume(1.5)
          visible: root.maxVolume >= 1.5
        }
      }
    }
  }

  function logEvent(message) {
    if (!root.debugLogging)
      return
    console.log("WireplumberModule " + new Date().toISOString() + " " + message)
  }

  function iconForVolume() {
    if (root.muted)
      return root.mutedIcon
    if (root.volumePercent <= 0)
      return root.icons[0]
    if (root.volumePercent < 34)
      return root.icons[1]
    if (root.volumePercent < 67)
      return root.icons[2]
    return root.icons[3]
  }

  function sinkLabel() {
    if (!root.sink)
      return ""
    if (root.sink.description && root.sink.description !== "")
      return root.sink.description
    if (root.sink.name && root.sink.name !== "")
      return root.sink.name
    return ""
  }

  function averageVolume(values) {
    let sum = 0
    for (let i = 0; i < values.length; i++)
      sum += values[i]
    return values.length > 0 ? sum / values.length : NaN
  }

  function resolveVolumeValue() {
    if (!root.sinkAudio || !root.pipewireReady)
      return NaN
    const values = root.sinkAudio.volumes
    if (values && values.length > 0)
      return root.averageVolume(values)
    return root.sinkAudio.volume
  }

  function adjustVolume(delta) {
    if (root.sinkAudio) {
      const next = Math.max(0, Math.min(root.maxVolume, root.sinkAudio.volume + delta))
      root.sinkAudio.volume = next
      return
    }
    const command = delta > 0 ? root.onScrollUpCommand : root.onScrollDownCommand
    Quickshell.execDetached(["sh", "-c", command])
  }

  function setVolume(value) {
    const next = Math.max(0, Math.min(root.maxVolume, value))
    if (root.sinkAudio && root.pipewireReady) {
      root.sinkAudio.volume = next
      return
    }
    const percent = Math.round(next * 100)
    Quickshell.execDetached([
      "sh",
      "-c",
      "wpctl set-volume -l " + root.maxVolume + " @DEFAULT_AUDIO_SINK@ " + percent + "%"
    ])
  }

  function toggleMute() {
    if (root.sinkAudio && root.pipewireReady) {
      root.sinkAudio.muted = !root.sinkAudio.muted
      return
    }
    Quickshell.execDetached(["sh", "-c", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"])
  }

  function refreshSink() {
    root.logEvent("refreshSink")
    root.sink = Pipewire.defaultAudioSink
    root.sinkAudio = root.sink ? root.sink.audio : null
    root.syncVolume()
  }

  function syncVolume() {
    if (!root.sinkAudio || !root.pipewireReady) {
      root.volumeAvailable = false
      root.volumePercent = 0
      root.muted = false
      root.sliderValue = 0
      root.logEvent("syncVolume unavailable")
      return
    }
    const volume = root.resolveVolumeValue()
    if (!isFinite(volume)) {
      root.volumeAvailable = false
      root.volumePercent = 0
      root.muted = false
      root.logEvent("syncVolume invalid")
      return
    }
    root.volumeAvailable = true
    root.volumePercent = Math.round(volume * 100)
    root.muted = !!root.sinkAudio.muted
    root.sliderValue = Math.max(0, Math.min(root.maxVolume, volume))
    root.logEvent("syncVolume ok percent=" + root.volumePercent + " muted=" + root.muted)
  }

  PwObjectTracker {
    objects: root.sink ? [root.sink] : []
  }

  Connections {
    target: Pipewire
    function onDefaultAudioSinkChanged() {
      root.logEvent("defaultAudioSinkChanged")
      root.refreshSink()
    }
    function onReadyChanged() {
      root.logEvent("pipewireReadyChanged")
      root.refreshSink()
    }
  }

  Connections {
    target: root.sink
    function onReadyChanged() {
      root.logEvent("sinkReadyChanged")
      root.syncVolume()
    }
  }

  Connections {
    target: root.sinkAudio
    function onMutedChanged() {
      root.logEvent("mutedChanged")
      root.syncVolume()
    }
    function onVolumesChanged() {
      root.logEvent("volumesChanged")
      root.syncVolume()
    }
  }

  Component.onCompleted: root.refreshSink()

  content: [
    IconLabel {
      text: root.iconForVolume()
      color: root.muted ? Config.red : Config.pink
    }
  ]

  MouseArea {
    anchors.fill: parent
    onWheel: function(wheel) {
      if (wheel.angleDelta.y > 0)
        root.adjustVolume(root.volumeStep)
      else if (wheel.angleDelta.y < 0)
        root.adjustVolume(-root.volumeStep)
    }
  }
}
