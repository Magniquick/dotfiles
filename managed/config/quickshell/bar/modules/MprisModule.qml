import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import ".."
import "../components"

ModuleContainer {
  id: root
  property int maxLength: 45
  property string fallbackText: ""
  property var activePlayer: null
  readonly property var players: Mpris.players.values
  readonly property string statusText: root.activePlayer
    ? root.statusIcon(root.activePlayer.playbackState)
    : ""
  readonly property string trackFullText: root.formatTrackText(root.activePlayer)
  readonly property string trackText: root.clampText(root.trackFullText)
  readonly property bool hasContent: root.statusText !== "" || root.trackFullText !== ""
  tooltipTitle: root.activePlayer && root.activePlayer.identity
    ? root.activePlayer.identity
    : "Now Playing"
  tooltipHoverable: true
  tooltipText: root.trackFullText
  tooltipContent: Component {
    ColumnLayout {
      spacing: Config.space.sm

      TooltipCard {
        content: [
          Text {
            text: root.trackFullText !== "" ? root.trackFullText : "Nothing playing"
            color: Config.textColor
            font.family: Config.fontFamily
            font.pixelSize: Config.fontSize + 1
            wrapMode: Text.Wrap
            Layout.preferredWidth: 320
            Layout.maximumWidth: 360
          }
        ]
      }

      TooltipCard {
        content: [
          RowLayout {
            spacing: Config.space.sm

            ActionIconButton {
              icon: ""
              enabled: !!root.activePlayer
              visible: root.activePlayer && root.activePlayer.canGoPrevious
              onClicked: if (root.activePlayer) root.activePlayer.previous()
            }

            ActionIconButton {
              icon: root.activePlayer && root.activePlayer.playbackState === MprisPlaybackState.Playing
                ? ""
                : ""
              enabled: !!root.activePlayer && root.activePlayer.canTogglePlaying
              onClicked: if (root.activePlayer && root.activePlayer.canTogglePlaying) root.activePlayer.togglePlaying()
            }

            ActionIconButton {
              icon: ""
              enabled: !!root.activePlayer && root.activePlayer.canGoNext
              onClicked: if (root.activePlayer && root.activePlayer.canGoNext) root.activePlayer.next()
            }

            Item { Layout.fillWidth: true }

            ActionChip {
              text: "Shuffle"
              active: root.activePlayer && root.activePlayer.shuffle
              visible: root.activePlayer && root.activePlayer.shuffleSupported
              onClicked: {
                if (root.activePlayer && root.activePlayer.canControl && root.activePlayer.shuffleSupported)
                  root.activePlayer.shuffle = !root.activePlayer.shuffle
              }
            }

            ActionChip {
              text: "Raise"
              visible: root.activePlayer && root.activePlayer.canRaise
              onClicked: if (root.activePlayer && root.activePlayer.canRaise) root.activePlayer.raise()
            }
          }
        ]
      }
    }
  }
  collapsed: !root.activePlayer || !root.hasContent

  function statusIcon(status) {
    if (status === MprisPlaybackState.Playing)
      return ""
    if (status === MprisPlaybackState.Paused)
      return ""
    return ""
  }

  function clampText(text) {
    if (!text)
      return ""
    if (text.length <= root.maxLength)
      return text
    return text.slice(0, root.maxLength - 3) + "..."
  }

  function isIgnoredPlayer(player) {
    if (!player)
      return true
    const dbusName = player.dbusName ? player.dbusName.toLowerCase() : ""
    const identity = player.identity ? player.identity.toLowerCase() : ""
    const desktopEntry = player.desktopEntry ? player.desktopEntry.toLowerCase() : ""
    return dbusName.indexOf("playerctld") >= 0 ||
      identity === "playerctld" ||
      desktopEntry === "playerctld"
  }

  function formatTrackText(player) {
    if (!player)
      return root.fallbackText
    const artist = player.trackArtist || ""
    const title = player.trackTitle || ""
    const artistTitle = [artist, title].filter(part => part !== "").join(" - ")
    return artistTitle ? artistTitle : root.fallbackText
  }

  function pickActivePlayer() {
    const list = (root.players || []).filter(player => !root.isIgnoredPlayer(player))
    for (let i = 0; i < list.length; i++) {
      const player = list[i]
      if (player && player.playbackState === MprisPlaybackState.Playing)
        return player
    }
    for (let i = 0; i < list.length; i++) {
      const player = list[i]
      if (player && player.playbackState === MprisPlaybackState.Paused)
        return player
    }
    return list.length > 0 ? list[0] : null
  }

  function refreshActivePlayer() {
    const selected = root.pickActivePlayer()
    if (selected !== root.activePlayer)
      root.activePlayer = selected
  }

  Connections {
    target: Mpris.players
    function onValuesChanged() {
      root.refreshActivePlayer()
    }
    function onObjectInsertedPost() {
      root.refreshActivePlayer()
    }
    function onObjectRemovedPost() {
      root.refreshActivePlayer()
    }
  }

  Repeater {
    model: Mpris.players
    delegate: Item {
      visible: false
      width: 0
      height: 0
      Connections {
        target: modelData
        function onPlaybackStateChanged() {
          root.refreshActivePlayer()
        }
        function onIsPlayingChanged() {
          root.refreshActivePlayer()
        }
        function onReady() {
          root.refreshActivePlayer()
        }
      }
    }
  }

  Component.onCompleted: root.refreshActivePlayer()

  content: [
    IconTextRow {
      spacing: root.contentSpacing
      iconText: root.statusText
      text: root.trackText
    }
  ]
}
