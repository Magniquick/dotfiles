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
pragma ComponentBehavior: Bound
import Quickshell
import ".."
import "../components"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris
import spotifylyrics 1.0

ModuleContainer {
    id: root

    property var activePlayer: null
    property bool debugLogging: false
    property int _positionBaseSeconds: 0
    property double _positionBasePreciseSeconds: 0
    property double _positionBaseMs: 0
    property double _positionNowMs: 0
    property var lyricsModel: []
    property int _lastLyricIndex: -2
    property int currentLyricIndex: -1
    property double _lyricsManualUntilMs: 0
    property string _lyricsTrackRef: ""
    readonly property string lyricsEnvFile: Config.envFile
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
    readonly property int displayPositionSeconds: {
        const player = root.activePlayer;
        if (!player)
            return 0;

        // If the tooltip is closed, avoid ticking; use the service value.
        if (!root.tooltipActive)
            return root.positionSeconds(player);

        const base = root._positionBaseSeconds;
        const baseMs = root._positionBaseMs;
        const nowMs = root._positionNowMs > 0 ? root._positionNowMs : Date.now();
        const playing = player.playbackState === MprisPlaybackState.Playing;
        const delta = (playing && baseMs > 0) ? Math.max(0, Math.floor((nowMs - baseMs) / 1000)) : 0;
        const length = root.lengthSeconds(player);
        return root.clampNumber(base + delta, 0, Math.max(0, length));
    }

    function updateLyricsModel() {
        if (!root.tooltipActive) {
            root.lyricsModel = [];
            root._lastLyricIndex = -2;
            root.currentLyricIndex = -1;
            return;
        }

        if (!root.activePlayer || !root.hasTrack) {
            root.lyricsModel = [{ text: "♪", isCurrent: true }];
            root.currentLyricIndex = -1;
            return;
        }

        const trackRef = root.spotifyLyricsTrackRef(root.activePlayer);
        if (!trackRef) {
            root.lyricsModel = [{ text: "♪ Lyrics unavailable ♪", isCurrent: true }];
            root.currentLyricIndex = -1;
            return;
        }

        if (lyricsClient.error && lyricsClient.error !== "") {
            root.lyricsModel = [{ text: "Lyrics error: " + lyricsClient.error, isCurrent: true }];
            root.currentLyricIndex = -1;
            return;
        }

        if (!lyricsClient.loaded) {
            root.lyricsModel = [{ text: lyricsClient.busy ? "Loading lyrics..." : "♪ No lyrics available ♪", isCurrent: true }];
            root.currentLyricIndex = -1;
            return;
        }

        const lines = lyricsClient.lines;
        if (!lines || lines.length === 0) {
            root.lyricsModel = [{ text: "♪ No lyrics available ♪", isCurrent: true }];
            root.currentLyricIndex = -1;
            return;
        }

        // Use millisecond-resolution position to avoid "whole-second" lag.
        const player = root.activePlayer;
        const playing = player && player.playbackState === MprisPlaybackState.Playing;
        const baseMs = root._positionBaseMs;
        const basePosSec = root._positionBasePreciseSeconds;
        const deltaMs = (playing && baseMs > 0) ? Math.max(0, Date.now() - baseMs) : 0;
        const posMs = Math.max(0, Math.floor(basePosSec * 1000 + deltaMs));
        let currentIndex = -1;

        for (let i = lines.length - 1; i >= 0; i--) {
            const startMs = parseInt(lines[i].startTimeMs);
            if (!isFinite(startMs))
                continue;
            if (posMs >= startMs) {
                currentIndex = i;
                break;
            }
        }

        if (currentIndex === -1) {
            root.lyricsModel = [{ text: "♪", isCurrent: true }];
            root.currentLyricIndex = -1;
            return;
        }

        if (currentIndex === root._lastLyricIndex)
            return;
        root._lastLyricIndex = currentIndex;
        root.currentLyricIndex = currentIndex;
        // Keep the old placeholder model for error/loading states; the UI reads
        // lyricsClient.lines for the scrollable view when loaded.
        root.lyricsModel = [];
    }

    function spotifyLyricsTrackRef(player) {
        if (!player)
            return "";

        // Avoid wasting requests for non-Spotify players.
        const desktopEntry = player.desktopEntry ? String(player.desktopEntry).toLowerCase() : "";
        const identity = player.identity ? String(player.identity).toLowerCase() : "";
        if (desktopEntry.indexOf("spotify") < 0 && identity.indexOf("spotify") < 0)
            return "";

        const md = player.metadata || ({});

        // Prefer xesam:url, if present (often a https://open.spotify.com/track/... URL).
        const xesamUrl = md["xesam:url"];
        if (typeof xesamUrl === "string" && xesamUrl !== "")
            return xesamUrl;
        if (Array.isArray(xesamUrl) && xesamUrl.length > 0 && typeof xesamUrl[0] === "string")
            return xesamUrl[0];

        // Fall back to mpris:trackid, which for Spotify commonly ends in the 22-char track ID.
        const mprisTrackId = md["mpris:trackid"];
        if (typeof mprisTrackId === "string" && mprisTrackId !== "") {
            const parts = mprisTrackId.split("/");
            const last = parts.length > 0 ? parts[parts.length - 1] : "";
            if (last)
                return last;
        }

        // Last resort: uniqueId sometimes looks like a stable identifier, but is not guaranteed.
        const uniqueId = player.uniqueId ? String(player.uniqueId) : "";
        if (/^[A-Za-z0-9]{22}$/.test(uniqueId))
            return uniqueId;

        return "";
    }

    function scheduleLyricsRefresh() {
        if (!root.tooltipActive)
            return;
        lyricsRefreshDebounce.stop();
        lyricsRefreshDebounce.start();
    }

    function refreshLyricsNow() {
        if (!root.tooltipActive)
            return;

        const ref = root.spotifyLyricsTrackRef(root.activePlayer);
        if (!ref) {
            root._lyricsTrackRef = "";
            root.updateLyricsModel();
            return;
        }

        if (ref === root._lyricsTrackRef && (lyricsClient.loaded || lyricsClient.busy)) {
            root.updateLyricsModel();
            return;
        }

        root._lyricsTrackRef = ref;
        lyricsClient.refreshFromEnv(root.lyricsEnvFile, ref);
        root.updateLyricsModel();
    }

    SpotifyLyricsClient {
        id: lyricsClient
    }

    Timer {
        id: lyricsRefreshDebounce
        interval: 200
        repeat: false
        running: false
        onTriggered: root.refreshLyricsNow()
    }

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
    function _syncPositionBase() {
        const player = root.activePlayer;
        const pos = player ? Number(player.position) : 0;
        const safePrecise = isFinite(pos) ? Math.max(0, pos) : 0;
        root._positionBasePreciseSeconds = safePrecise;
        root._positionBaseSeconds = Math.max(0, Math.floor(safePrecise));
        root._positionBaseMs = Date.now();
        root._positionNowMs = root._positionBaseMs;
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
    onActivePlayerChanged: {
        root._syncPositionBase();
        root._lastLyricIndex = -2;
        root.scheduleLyricsRefresh();
    }
    onDisplayPositionSecondsChanged: root.updateLyricsModel()
    onTooltipActiveChanged: {
        root._lastLyricIndex = -2;
        if (root.tooltipActive)
            root.scheduleLyricsRefresh();
        root.updateLyricsModel();
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
                    Layout.preferredHeight: Math.max(detailsColumn.implicitHeight, Config.space.xxl * 2 + Config.space.sm)
                    Layout.preferredWidth: Layout.preferredHeight
                    implicitHeight: Layout.preferredHeight
                    implicitWidth: Layout.preferredWidth
                    radius: Config.shape.corner.md

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
                        Loader {
                            anchors.fill: parent
                            active: root.tooltipActive && root.hasArt && artImage.status === Image.Ready
                            sourceComponent: OpacityMask {
                                anchors.fill: parent
                                cached: true
                                source: artImage
                                maskSource: artMask
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        color: Config.color.on_surface_variant
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

                                color: Config.color.on_surface
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
                                running: titleClip.hovered
                                    && titleClip.scrollDistance > 0
                                    && root.visible
                                    && root.QsWindow.window && root.QsWindow.window.visible

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
                            color: Config.color.on_surface_variant
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
                            fillColor: Config.color.primary
                            maximum: Math.max(1, root.lengthSeconds(root.activePlayer))
                            minimum: 0
                            value: root.displayPositionSeconds

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
                            color: Config.color.surface_container_highest
                            border.color: Config.color.outline
                            border.width: 1
                            radius: Config.shape.corner.xs
                            width: seekPreviewText.implicitWidth + Config.space.sm
                            height: seekPreviewText.implicitHeight + Config.space.xs
                            x: Math.max(0, Math.min(parent.width - width, progressSlider.hoverRatio * parent.width - width / 2))
                            y: -height - Config.space.xs

                            Text {
                                id: seekPreviewText
                                anchors.centerIn: parent
                                color: Config.color.on_surface
                                font.family: Config.fontFamily
                                font.pixelSize: Config.type.labelSmall.size
                                text: root.formatTime(progressSlider.hoverRatio * root.lengthSeconds(root.activePlayer))
                            }
                        }
                    }
                    RowLayout {
                        spacing: Config.space.xs

                        Text {
                            color: Config.color.on_surface_variant
                            font.family: Config.fontFamily
                            font.pixelSize: Config.type.labelSmall.size
                            text: {
                                const total = root.lengthSeconds(root.activePlayer);
                                const elapsed = total > 0 ? root.formatTime(root.displayPositionSeconds) : "--:--";
                                if (total <= 0)
                                    return elapsed;
                                return elapsed + " / " + root.formatTime(total);
                            }
                        }
                        // Seek unavailable indicator
                        Text {
                            visible: root.activePlayer && !root.activePlayer.canSeek
                            color: Config.color.on_surface_variant
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

            Rectangle {
                Layout.fillWidth: true
                // 3 visible lyric rows + vertical padding.
                Layout.preferredHeight: Config.type.bodyLarge.size * 3 + Config.space.md * 4
                border.color: Qt.alpha(Config.color.outline_variant, 0.55)
                border.width: 1
                clip: true
                color: Qt.alpha(Config.color.surface_container_highest, 0.45)
                radius: Config.shape.corner.md

                Item {
                    anchors.fill: parent
                    anchors.margins: Config.space.md

                    readonly property bool lyricsLoaded: lyricsClient.loaded && lyricsClient.lines && lyricsClient.lines.length > 0

                    // Placeholder / error / loading text
                    Text {
                        anchors.centerIn: parent
                        visible: !parent.lyricsLoaded
                        color: Config.color.on_surface_variant
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.bodyMedium.size
                        horizontalAlignment: Text.AlignHCenter
                        lineHeight: 1.1
                        lineHeightMode: Text.ProportionalHeight
                        maximumLineCount: 2
                        opacity: 0.8
                        text: (root.lyricsModel && root.lyricsModel.length > 0) ? root.lyricsModel[0].text : "Loading lyrics..."
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }

                    ListView {
                        id: lyricsView

                        anchors.fill: parent
                        clip: true
                        visible: parent.lyricsLoaded

                        model: lyricsClient.lines
                        spacing: Config.space.xs
                        interactive: true

                        // Use a bit of padding so centering feels intentional.
                        topMargin: Math.round(height * 0.28)
                        bottomMargin: topMargin

                        Behavior on contentY {
                            enabled: root.tooltipActive
                                && Date.now() > root._lyricsManualUntilMs
                                && !lyricsView.dragging
                                && !lyricsView.moving
                            NumberAnimation {
                                duration: Config.motion.duration.medium
                                easing.type: Easing.OutCubic
                            }
                        }

                        onMovementStarted: root._lyricsManualUntilMs = Date.now() + 1500
                        onMovementEnded: root._lyricsManualUntilMs = Date.now() + 700

                        ScrollIndicator.vertical: ScrollIndicator {
                            active: lyricsView.visible && root.tooltipActive
                            visible: active
                        }

                        delegate: Text {
                            required property var modelData
                            required property int index

                            readonly property string words: {
                                // modelData is a QVariantMap from C++.
                                if (modelData && modelData.words !== undefined)
                                    return String(modelData.words || "");
                                if (modelData && modelData["words"] !== undefined)
                                    return String(modelData["words"] || "");
                                return "";
                            }

                            readonly property bool isCurrent: index === root.currentLyricIndex

                            color: isCurrent ? Config.color.on_surface : Config.color.on_surface_variant
                            elide: Text.ElideRight
                            font.family: Config.fontFamily
                            font.pixelSize: isCurrent ? Config.type.bodyLarge.size : Config.type.bodyMedium.size
                            font.weight: isCurrent ? Font.DemiBold : Font.Normal
                            horizontalAlignment: Text.AlignHCenter
                            lineHeight: 1.1
                            lineHeightMode: Text.ProportionalHeight
                            maximumLineCount: 2
                            opacity: isCurrent ? 1.0 : 0.55
                            text: words !== "" ? words : "♪"
                            wrapMode: Text.WordWrap
                            width: ListView.view ? ListView.view.width : parent.width

                            Behavior on opacity {
                                enabled: root.tooltipActive
                                NumberAnimation {
                                    duration: Config.motion.duration.medium
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on font.pixelSize {
                                enabled: root.tooltipActive
                                NumberAnimation {
                                    duration: Config.motion.duration.medium
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on color {
                                enabled: root.tooltipActive
                                ColorAnimation { duration: Config.motion.duration.medium }
                            }
                        }

                        function followCurrent() {
                            if (!lyricsView.visible)
                                return;
                            if (root.currentLyricIndex < 0)
                                return;
                            if (Date.now() <= root._lyricsManualUntilMs)
                                return;
                            if (lyricsView.dragging || lyricsView.moving)
                                return;
                            Qt.callLater(function() {
                                if (!lyricsView.visible)
                                    return;
                                lyricsView.positionViewAtIndex(root.currentLyricIndex, ListView.Center);
                            });
                        }

                        Component.onCompleted: followCurrent()

                        Connections {
                            target: root
                            function onCurrentLyricIndexChanged() { lyricsView.followCurrent(); }
                            function onTooltipActiveChanged() { if (root.tooltipActive) lyricsView.followCurrent(); }
                        }

                        Connections {
                            target: lyricsClient
                            function onLoadedChanged() { lyricsView.followCurrent(); }
                            function onLinesChanged() { lyricsView.followCurrent(); }
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
            id: playerConnection

            required property var modelData

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

                target: playerConnection.modelData
            }
        }
    }
    Timer {
        interval: 200
        repeat: true
        running: root.tooltipActive && root.activePlayer && root.activePlayer.playbackState === MprisPlaybackState.Playing

        onTriggered: {
            root._positionNowMs = Date.now();
            root.updateLyricsModel();
        }
    }

    Connections {
        target: lyricsClient

        function onLoadedChanged() { root._lastLyricIndex = -2; root.updateLyricsModel(); }
        function onLinesChanged() { root._lastLyricIndex = -2; root.updateLyricsModel(); }
        function onErrorChanged() { root.updateLyricsModel(); }
        function onBusyChanged() { root.updateLyricsModel(); }
    }

    Connections {
        target: root.activePlayer

        function onPositionChanged() { root._syncPositionBase(); }
        function onTrackTitleChanged() { root._syncPositionBase(); root.scheduleLyricsRefresh(); }
        function onTrackArtistChanged() { root._syncPositionBase(); root.scheduleLyricsRefresh(); }
        function onPlaybackStateChanged() { root._syncPositionBase(); }
        function onUniqueIdChanged() { root.scheduleLyricsRefresh(); }
        function onMetadataChanged() { root.scheduleLyricsRefresh(); }
        function onReady() { root._syncPositionBase(); root.scheduleLyricsRefresh(); }
    }
}
