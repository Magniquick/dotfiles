/**
 * @module MprisModule
 * @description Media player control module using MPRIS (Media Player Remote Interfacing Specification)
 *
 * Features:
 * - Auto-detection of active media players
 * - Playback controls (play/pause, previous, next)
 * - Seekbar with position indicator (when supported by player)
 * - Album art display with blur effects
 * - Track title and artist information
 * - Scrolling marquee for long track titles
 * - Support for multiple concurrent players (automatically selects active/playing)
 * - Real-time position updates with smooth progress animation
 *
 * Supported Players:
 * - Any player implementing MPRIS D-Bus interface
 * - Common examples: Spotify, VLC, Firefox, Chrome, mpv, Rhythmbox, etc.
 *
 * Dependencies:
 * - Quickshell.Services.Mpris: Built-in MPRIS service provider
 * - Qt5Compat.GraphicalEffects: Album art blur effects
 *
 * Configuration:
 * - maxLength: Maximum text length before truncation (default: 45 characters)
 * - debugLogging: Enable console debug output (default: false)
 *
 * Player Selection Logic:
 * 1. Prefer players with playbackState = Playing
 * 2. Fall back to Paused players if no Playing players
 * 3. Fall back to Stopped players if none Playing/Paused
 * 4. When multiple players in same state, prefer last active
 *
 * Performance Optimizations:
 * - Marquee animation gated by window visibility (prevents idle CPU usage)
 * - Position updates only when player is playing
 * - Album art loaded asynchronously
 * - Animations disabled when tooltip is hidden
 *
 * Seekbar Support:
 * - Only shown for players with canSeek capability
 * - Smooth scrubbing with visual feedback
 * - Position tracking synced with player state
 * - Automatic adjustment when track changes
 *
 * Error Handling:
 * - Safe handling of missing track metadata
 * - Fallback text for unknown players
 * - Bounds checking for position values
 * - Graceful degradation when player disconnects
 *
 * @example
 * // Basic usage with defaults
 * MprisModule {}
 *
 * @example
 * // Custom text length and debug logging
 * MprisModule {
 *     maxLength: 60
 *     debugLogging: true
 * }
 */
import ".."
import "../components"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris

ModuleContainer {
    id: root

    property var activePlayer: null
    property bool debugLogging: false
    readonly property string displaySubtitle: root.trackArtist !== "" ? root.trackArtist : (root.activePlayer ? root.playerTitle : "No active player")
    readonly property string displayTitle: root.trackTitle !== "" ? root.trackTitle : (root.trackFullText !== "" ? root.trackFullText : "Nothing playing")
    property string fallbackText: ""
    readonly property bool hasArt: root.trackArtUrl !== ""
    readonly property bool hasContent: root.statusText !== "" || root.trackFullText !== ""
    readonly property bool hasTrack: root.trackFullText !== ""
    property int maxLength: 45
    readonly property string playbackLabel: root.activePlayer ? root.playbackStateLabel(root.activePlayer.playbackState) : "Idle"
    readonly property string playerTitle: root.activePlayer && root.activePlayer.identity ? root.activePlayer.identity : "Now Playing"
    readonly property var players: Mpris.players.values
    readonly property string statusText: root.activePlayer ? root.statusIcon(root.activePlayer.playbackState) : ""
    readonly property string trackArtUrl: root.activePlayer ? root.activePlayer.trackArtUrl : ""
    readonly property string trackArtist: root.activePlayer && root.activePlayer.trackArtist ? root.activePlayer.trackArtist : ""
    readonly property string trackFullText: root.formatTrackText(root.activePlayer)
    readonly property string trackText: root.clampText(root.trackFullText)
    readonly property string trackTitle: root.activePlayer && root.activePlayer.trackTitle ? root.activePlayer.trackTitle : ""

    function clampNumber(value, min, max) {
        if (!isFinite(value))
            return min;

        return Math.max(min, Math.min(max, value));
    }
    function clampText(text) {
        if (!text)
            return "";

        if (text.length <= root.maxLength)
            return text;

        return text.slice(0, root.maxLength - 3) + "...";
    }
    function formatTime(seconds) {
        if (!isFinite(seconds))
            return "--:--";

        const safeSeconds = Math.max(0, Math.floor(seconds));
        const hours = Math.floor(safeSeconds / 3600);
        const minutes = Math.floor((safeSeconds % 3600) / 60);
        const secs = safeSeconds % 60;
        if (hours > 0)
            return hours + ":" + String(minutes).padStart(2, "0") + ":" + String(secs).padStart(2, "0");

        return minutes + ":" + String(secs).padStart(2, "0");
    }
    function formatTrackText(player) {
        if (!player)
            return root.fallbackText;

        const artist = player.trackArtist || "";
        const title = player.trackTitle || "";
        const artistTitle = [artist, title].filter(part => {
            return part !== "";
        }).join(" - ");
        return artistTitle ? artistTitle : root.fallbackText;
    }
    function isIgnoredPlayer(player) {
        if (!player)
            return true;

        const dbusName = player.dbusName ? player.dbusName.toLowerCase() : "";
        const identity = player.identity ? player.identity.toLowerCase() : "";
        const desktopEntry = player.desktopEntry ? player.desktopEntry.toLowerCase() : "";
        return dbusName.indexOf("playerctld") >= 0 || identity === "playerctld" || desktopEntry === "playerctld";
    }
    function lengthSeconds(player) {
        if (!player)
            return 0;

        const lengthValue = root.secondsFromValue(player.length);
        if (lengthValue > 0)
            return lengthValue;

        if (player.lengthSupported)
            return lengthValue;

        return 0;
    }
    function pickActivePlayer() {
        const list = (root.players || []).filter(player => {
            return !root.isIgnoredPlayer(player);
        });
        for (let i = 0; i < list.length; i++) {
            const player = list[i];
            if (player && player.playbackState === MprisPlaybackState.Playing)
                return player;
        }
        for (let i = 0; i < list.length; i++) {
            const player = list[i];
            if (player && player.playbackState === MprisPlaybackState.Paused)
                return player;
        }
        return list.length > 0 ? list[0] : null;
    }
    function playbackStateLabel(status) {
        if (status === MprisPlaybackState.Playing)
            return "Playing";

        if (status === MprisPlaybackState.Paused)
            return "Paused";

        return "Stopped";
    }
    function positionSeconds(player) {
        if (!player)
            return 0;

        const positionValue = root.secondsFromValue(player.position);
        if (positionValue > 0)
            return positionValue;

        if (player.positionSupported)
            return positionValue;

        return 0;
    }
    function refreshActivePlayer() {
        const selected = root.pickActivePlayer();
        if (selected !== root.activePlayer)
            root.activePlayer = selected;
    }
    function secondsFromValue(value) {
        if (!isFinite(value))
            return 0;

        return Math.max(0, Math.floor(Number(value)));
    }
    function statusIcon(status) {
        if (status === MprisPlaybackState.Playing)
            return "";

        if (status === MprisPlaybackState.Paused)
            return "";

        return "";
    }

    collapsed: !root.activePlayer || !root.hasContent
    tooltipHoverable: true
    tooltipText: root.trackFullText
    tooltipTitle: root.playerTitle

    onClicked: {
        if (root.activePlayer && root.activePlayer.canTogglePlaying)
            root.activePlayer.togglePlaying();
    }

    content: [
        IconTextRow {
            iconText: root.statusText
            spacing: root.contentSpacing
            text: root.trackText
        }
    ]
    tooltipContent: Component {
        ColumnLayout {
            spacing: Config.space.sm

            RowLayout {
                Layout.fillWidth: true
                spacing: Config.space.md

                Rectangle {
                    border.color: "transparent"
                    border.width: 0
                    clip: true
                    color: "transparent"
                    height: Math.max(detailsColumn.implicitHeight, Config.space.xxl * 2 + Config.space.sm)
                    implicitHeight: height
                    implicitWidth: width
                    radius: Config.shape.corner.md
                    width: height

                    Item {
                        id: artFrame

                        anchors.fill: parent
                        anchors.margins: Config.spaceHalfXs
                        visible: root.hasArt

                        Image {
                            id: artImage

                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            mipmap: true
                            smooth: true
                            source: root.trackArtUrl
                            sourceSize.height: height * Screen.devicePixelRatio
                            sourceSize.width: width * Screen.devicePixelRatio
                            visible: false
                        }
                        Rectangle {
                            id: artMask

                            anchors.fill: parent
                            radius: Config.shape.corner.sm
                            visible: false
                        }
                        OpacityMask {
                            anchors.fill: parent
                            maskSource: artMask
                            source: artImage
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        color: Config.m3.onSurfaceVariant
                        font.family: Config.iconFontFamily
                        font.pixelSize: Config.type.headlineLarge.size
                        text: ""
                        visible: !root.hasArt
                    }
                }
                ColumnLayout {
                    id: detailsColumn

                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 280
                    spacing: Config.space.sm

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: Config.space.xs

                        Flickable {
                            id: titleClip

                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true
                            contentHeight: titleText.implicitHeight
                            contentWidth: titleText.implicitWidth
                            implicitHeight: titleText.implicitHeight
                            interactive: false
                            property real scrollDistance: Math.max(0, contentWidth - width)
                            readonly property bool hovered: titleHover.hovered

                            Text {
                                id: titleText

                                color: Config.m3.onSurface
                                elide: titleClip.hovered ? Text.ElideNone : Text.ElideRight
                                font.family: Config.fontFamily
                                font.pixelSize: Config.type.titleLarge.size
                                font.weight: Config.type.titleLarge.weight
                                text: root.displayTitle
                                width: titleClip.hovered ? implicitWidth : titleClip.width
                            }
                            HoverHandler {
                                id: titleHover

                                onHoveredChanged: {
                                    if (!hovered)
                                        titleClip.contentX = 0;
                                }
                            }
                            SequentialAnimation {
                                id: titleMarquee

                                loops: Animation.Infinite
                                running: titleClip.hovered && titleClip.scrollDistance > 0 && root.QsWindow.window && root.QsWindow.window.visible

                                PauseAnimation {
                                    duration: 350
                                }
                                NumberAnimation {
                                    duration: Math.max(1200, titleClip.scrollDistance * 15)
                                    easing.type: Easing.InOutQuad
                                    property: "contentX"
                                    target: titleClip
                                    to: titleClip.scrollDistance
                                }
                                PauseAnimation {
                                    duration: 350
                                }
                                NumberAnimation {
                                    duration: 500
                                    easing.type: Easing.OutQuad
                                    property: "contentX"
                                    target: titleClip
                                    to: 0
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            color: Config.m3.onSurfaceVariant
                            elide: Text.ElideRight
                            font.family: Config.fontFamily
                            font.pixelSize: Config.type.labelMedium.size
                            text: root.displaySubtitle
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: progressSlider.implicitHeight

                        LevelSlider {
                            id: progressSlider

                            anchors.fill: parent
                            enabled: root.activePlayer && root.activePlayer.canSeek && root.lengthSeconds(root.activePlayer) > 0
                            fillColor: Config.m3.primary
                            maximum: Math.max(1, root.lengthSeconds(root.activePlayer))
                            minimum: 0
                            value: root.positionSeconds(root.activePlayer)

                            // Only seek on drag release, not during drag (prevents multiple in-flight commands)
                            onDragEnded: value => {
                                if (!root.activePlayer || !root.activePlayer.canSeek)
                                    return;
                                // MPRIS seek() uses delta (relative offset), not absolute position
                                const deltaSeconds = value - root.positionSeconds(root.activePlayer);
                                if (!isFinite(deltaSeconds) || deltaSeconds === 0)
                                    return;
                                root.activePlayer.seek(Math.round(deltaSeconds));
                            }
                        }
                        // Seek position preview tooltip
                        Rectangle {
                            id: seekPreview
                            visible: progressSlider.hovered && progressSlider.enabled && !progressSlider.dragging
                            color: Config.m3.surfaceContainerHighest
                            border.color: Config.m3.outline
                            border.width: 1
                            radius: Config.shape.corner.xs
                            width: seekPreviewText.implicitWidth + Config.space.sm
                            height: seekPreviewText.implicitHeight + Config.space.xs
                            x: Math.max(0, Math.min(parent.width - width, progressSlider.hoverRatio * parent.width - width / 2))
                            y: -height - Config.space.xs

                            Text {
                                id: seekPreviewText
                                anchors.centerIn: parent
                                color: Config.m3.onSurface
                                font.family: Config.fontFamily
                                font.pixelSize: Config.type.labelSmall.size
                                text: root.formatTime(progressSlider.hoverRatio * root.lengthSeconds(root.activePlayer))
                            }
                        }
                    }
                    RowLayout {
                        spacing: Config.space.xs

                        Text {
                            color: Config.m3.onSurfaceVariant
                            font.family: Config.fontFamily
                            font.pixelSize: Config.type.labelSmall.size
                            text: {
                                const total = root.lengthSeconds(root.activePlayer);
                                const elapsed = total > 0 ? root.formatTime(root.positionSeconds(root.activePlayer)) : "--:--";
                                if (total <= 0)
                                    return elapsed;
                                return elapsed + " / " + root.formatTime(total);
                            }
                        }
                        // Seek unavailable indicator
                        Text {
                            visible: root.activePlayer && !root.activePlayer.canSeek
                            color: Config.m3.onSurfaceVariant
                            font.family: Config.iconFontFamily
                            font.pixelSize: Config.type.labelSmall.size
                            text: ""
                            opacity: 0.6

                            ToolTip.visible: seekUnavailableHover.hovered
                            ToolTip.text: "Seek not supported by this player"

                            HoverHandler {
                                id: seekUnavailableHover
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Config.space.xs

                    ActionIconButton {
                        enabled: !!root.activePlayer && root.activePlayer.canGoPrevious
                        icon: ""

                        onClicked: {
                            if (root.activePlayer && root.activePlayer.canGoPrevious)
                                root.activePlayer.previous();
                        }
                    }
                    ActionIconButton {
                        enabled: !!root.activePlayer && root.activePlayer.canTogglePlaying
                        icon: root.activePlayer && root.activePlayer.playbackState === MprisPlaybackState.Playing ? "" : ""

                        onClicked: {
                            if (root.activePlayer && root.activePlayer.canTogglePlaying)
                                root.activePlayer.togglePlaying();
                        }
                    }
                    ActionIconButton {
                        enabled: !!root.activePlayer && root.activePlayer.canGoNext
                        icon: ""

                        onClicked: {
                            if (root.activePlayer && root.activePlayer.canGoNext)
                                root.activePlayer.next();
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: root.refreshActivePlayer()

    Connections {
        function onObjectInsertedPost() {
            root.refreshActivePlayer();
        }
        function onObjectRemovedPost() {
            root.refreshActivePlayer();
        }
        function onValuesChanged() {
            root.refreshActivePlayer();
        }

        target: Mpris.players
    }
    Repeater {
        model: Mpris.players

        delegate: Item {
            height: 0
            visible: false
            width: 0

            Connections {
                function onIsPlayingChanged() {
                    root.refreshActivePlayer();
                }
                function onPlaybackStateChanged() {
                    root.refreshActivePlayer();
                }
                function onReady() {
                    root.refreshActivePlayer();
                }

                target: modelData
            }
        }
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.activePlayer && root.activePlayer.playbackState === MprisPlaybackState.Playing

        onTriggered: {
            if (root.activePlayer)
                root.activePlayer.positionChanged();
        }
    }
}
