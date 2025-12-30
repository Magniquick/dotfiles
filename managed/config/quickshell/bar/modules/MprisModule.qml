import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
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
                            sourceSize.height: 256
                            sourceSize.width: 256
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
                    spacing: Config.space.sm

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: Config.space.xs

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            color: Config.m3.onSurface
                            elide: Text.ElideRight
                            font.family: Config.fontFamily
                            font.pixelSize: Config.type.titleLarge.size
                            font.weight: Config.type.titleLarge.weight
                            text: root.displayTitle
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
                    LevelSlider {
                        Layout.fillWidth: true
                        enabled: root.activePlayer && root.activePlayer.canSeek && root.lengthSeconds(root.activePlayer) > 0
                        fillColor: Config.m3.primary
                        maximum: Math.max(1, root.lengthSeconds(root.activePlayer))
                        minimum: 0
                        value: root.positionSeconds(root.activePlayer)

                        onUserChanged: {
                            if (!root.activePlayer || !root.activePlayer.canSeek)
                                return;
                            const deltaSeconds = value - root.positionSeconds(root.activePlayer);
                            if (!isFinite(deltaSeconds) || deltaSeconds === 0)
                                return;
                            root.activePlayer.seek(Math.round(deltaSeconds));
                        }
                    }
                    Text {
                        color: Config.m3.onSurfaceVariant
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.labelSmall.size
                        text: {
                            const total = root.lengthSeconds(root.activePlayer);
                            const elapsed = total > 0 ? root.formatTime(root.positionSeconds(root.activePlayer)) : "--:--";
                            if (total <= 0)
                                return elapsed;
                            const remaining = root.clampNumber(total - root.positionSeconds(root.activePlayer), 0, total);
                            return elapsed + " / " + root.formatTime(remaining);
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
