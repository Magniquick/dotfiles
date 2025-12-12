import QtQuick
import QtQml
import "./Label.qml"
import "../theme"

Item {
  id: root
  property var mpris: null
  property bool available: false
  property var player: null
  property string statusIcon: ""
  property string text: ""
  property int maxLength: 45

  implicitHeight: label.implicitHeight
  implicitWidth: label.implicitWidth

  function createMpris() {
    const src = "import Quickshell.Services.Mpris; Mpris {}";
    const comp = Qt.createComponent(src);
    if (comp.status === Component.Ready) {
      mpris = comp.createObject(root);
      available = !!mpris;
    } else {
      comp.statusChanged.connect(function(status) {
        if (status === Component.Ready) {
          mpris = comp.createObject(root);
          available = !!mpris;
        }
      });
    }
  }

  function activePlayer() {
    if (!available || !mpris || !mpris.players)
      return null;
    const players = mpris.players.values || [];
    if (players.length === 0)
      return null;
    const playing = players.find(p => p.isPlaying);
    return playing || players[0];
  }

  function displayText(target) {
    if (!target)
      return "";
    const artist = target.trackArtist || (target.trackArtists && target.trackArtists[0]) || "";
    const title = target.trackTitle || "";
    if (!artist && !title)
      return "";
    return `${artist} - ${title}`.trim();
  }

  function truncated(str) {
    if (!str)
      return "";
    if (str.length <= maxLength)
      return str;
    return `${str.slice(0, Math.max(0, maxLength - 3))}...`;
  }

  function update() {
    if (!available) {
      player = null;
      text = "";
      statusIcon = "";
      return;
    }
    const current = activePlayer();
    player = current;
    text = displayText(current);
    const playing = current && current.isPlaying;
    statusIcon = playing ? "" : "";
  }

  Component.onCompleted: createMpris()

  Connections {
    target: mpris ? mpris.players : null
    function onModelReset() { update(); }
    function onRowsInserted() { update(); }
    function onRowsRemoved() { update(); }
  }

  Connections {
    target: mpris
    function onPlayersChanged() { update(); }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: update()
  }

  Label {
    id: label
    text: {
      const combined = text ? `${statusIcon} ${text}` : "";
      return root.truncated(combined);
    }
    elide: Text.ElideRight
  }
}
