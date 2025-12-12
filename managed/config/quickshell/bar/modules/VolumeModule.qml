import QtQuick
import QtQuick.Controls
import QtQml
import Quickshell
import "./Label.qml"
import "../theme"

Item {
  id: root
  property var pipewire: null
  property var tracker: null
  property var sinkNode: null
  property var currentAudio: null
  property real volume: currentAudio && currentAudio.volume ? currentAudio.volume : 0
  property bool muted: currentAudio && currentAudio.muted
  property string deviceLabel: ""
  property string icon: muted ? "" : volumeIcon(volume)
  property bool available: false

  visible: available
  implicitHeight: label.implicitHeight
  implicitWidth: label.implicitWidth

  function createPipewire() {
    const src = "import Quickshell.Services.Pipewire; Pipewire {}";
    const comp = Qt.createComponent(src);
    if (comp.status === Component.Ready) {
      pipewire = comp.createObject(root);
      available = !!pipewire;
      createTracker();
      updateSink();
    } else {
      comp.statusChanged.connect(function(status) {
        if (status === Component.Ready) {
          pipewire = comp.createObject(root);
          available = !!pipewire;
          createTracker();
          updateSink();
        }
      });
    }
  }

  function createTracker() {
    if (!pipewire) return;
    const src = "import Quickshell.Services.Pipewire; PwObjectTracker { objects: [] }";
    const comp = Qt.createComponent(src);
    if (comp.status === Component.Ready) {
      tracker = comp.createObject(root);
    } else {
      comp.statusChanged.connect(function(status) {
        if (status === Component.Ready) {
          tracker = comp.createObject(root);
        }
      });
    }
  }

  function volumeIcon(vol) {
    const pct = Math.round(vol * 100);
    if (pct === 0) return "";
    if (pct < 50) return "";
    return "";
  }

  function updateSink() {
    sinkNode = pipewire ? pipewire.defaultAudioSink : null;
    if (tracker)
      tracker.objects = [ sinkNode ];
    updateAudio();
  }

  function updateAudio() {
    currentAudio = sinkNode && sinkNode.audio ? sinkNode.audio : null;
    volume = currentAudio && currentAudio.volume ? currentAudio.volume : 0;
    muted = currentAudio && currentAudio.muted;
    deviceLabel = sinkNode ? (sinkNode.description || sinkNode.name || "") : "";
    icon = muted ? "" : volumeIcon(volume);
  }

  Component.onCompleted: createPipewire()

  Connections {
    target: pipewire
    function onDefaultAudioSinkChanged() { updateSink(); }
  }

  Connections {
    target: currentAudio
    function onVolumeChanged() { updateAudio(); }
    function onMutedChanged() { updateAudio(); }
  }

  Label {
    id: label
    text: icon
    color: muted ? Theme.colors.red : Theme.colors.pink
    ToolTip.visible: mouseArea.containsMouse
    ToolTip.text: {
      const pct = Math.round(volume * 100);
      const device = deviceLabel || "Default output";
      const status = muted ? " (muted)" : "";
      return `Volume: ${pct}%${status}\nDevice: ${device}`;
    }
  }

  MouseArea {
    anchors.fill: parent
    id: mouseArea
    hoverEnabled: true
    acceptedButtons: Qt.AllButtons
    scrollGestureEnabled: true
    onWheel: wheel => {
      const delta = wheel.angleDelta.y;
      if (delta === 0) return;
      const change = delta > 0 ? "1%+" : "1%-";
      Quickshell.execDetached({
        command: [ "wpctl", "set-volume", "-l", "2", "@DEFAULT_AUDIO_SINK@", change ],
      });
    }
  }
}
