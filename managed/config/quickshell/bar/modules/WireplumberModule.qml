pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import ".."
import "../components"

ModuleContainer {
    id: root

    property bool debugLogging: false
    property var icons: ["", "", "", ""]
    property real maxVolume: 2.0
    property bool muted: false
    property string mutedIcon: ""
    property string onScrollDownCommand: "wpctl set-volume -l 2 @DEFAULT_AUDIO_SINK@ 1%-"
    property string onScrollUpCommand: "wpctl set-volume -l 2 @DEFAULT_AUDIO_SINK@ 1%+"
    readonly property bool pipewireReady: root.sink ? root.sink.ready : false
    property var sink: Pipewire.defaultAudioSink
    property var sinkAudio: root.sink ? root.sink.audio : null
    property real sliderValue: 0
    property bool volumeAvailable: false
    property int volumePercent: 0
    property real volumeStep: 0.01

    function activeColor() {
        return (root.muted || root.volumePercent > 100) ? Config.m3.error : Config.m3.secondary;
    }
    function adjustVolume(delta) {
        if (root.sinkAudio) {
            const next = Math.max(0, Math.min(root.maxVolume, root.sinkAudio.volume + delta));
            root.sinkAudio.volume = next;
            return;
        }
        const command = delta > 0 ? root.onScrollUpCommand : root.onScrollDownCommand;
        Quickshell.execDetached(["sh", "-c", command]);
    }
    function averageVolume(values) {
        let sum = 0;
        for (let i = 0; i < values.length; i++)
            sum += values[i];
        return values.length > 0 ? sum / values.length : NaN;
    }
    function iconForVolume() {
        if (root.muted)
            return root.mutedIcon;
        if (root.volumePercent <= 0)
            return root.icons[0];
        if (root.volumePercent < 34)
            return root.icons[1];
        if (root.volumePercent < 67)
            return root.icons[2];
        return root.icons[3];
    }
    function logEvent(message) {
        if (!root.debugLogging)
            return;
        console.log("WireplumberModule " + new Date().toISOString() + " " + message);
    }
    function refreshSink() {
        root.logEvent("refreshSink");
        root.sink = Pipewire.defaultAudioSink;
        root.sinkAudio = root.sink ? root.sink.audio : null;
        root.syncVolume();
    }
    function resolveVolumeValue() {
        if (!root.sinkAudio || !root.pipewireReady)
            return NaN;
        const values = root.sinkAudio.volumes;
        if (values && values.length > 0)
            return root.averageVolume(values);
        return root.sinkAudio.volume;
    }
    function setVolume(value) {
        const next = Math.max(0, Math.min(root.maxVolume, value));
        if (root.sinkAudio && root.pipewireReady) {
            root.sinkAudio.volume = next;
            return;
        }
        const percent = Math.round(next * 100);
        Quickshell.execDetached(["sh", "-c", "wpctl set-volume -l " + root.maxVolume + " @DEFAULT_AUDIO_SINK@ " + percent + "%"]);
    }
    function sinkLabel() {
        if (!root.sink)
            return "";
        if (root.sink.description && root.sink.description !== "")
            return root.sink.description;
        if (root.sink.name && root.sink.name !== "")
            return root.sink.name;
        return "";
    }
    function syncVolume() {
        if (!root.sinkAudio || !root.pipewireReady) {
            root.volumeAvailable = false;
            root.volumePercent = 0;
            root.muted = false;
            root.sliderValue = 0;
            root.logEvent("syncVolume unavailable");
            return;
        }
        const volume = root.resolveVolumeValue();
        if (!isFinite(volume)) {
            root.volumeAvailable = false;
            root.volumePercent = 0;
            root.muted = false;
            root.logEvent("syncVolume invalid");
            return;
        }
        root.volumeAvailable = true;
        root.volumePercent = Math.round(volume * 100);
        root.muted = !!root.sinkAudio.muted;
        root.sliderValue = Math.max(0, Math.min(root.maxVolume, volume));
        root.logEvent("syncVolume ok percent=" + root.volumePercent + " muted=" + root.muted);
    }
    function toggleMute() {
        if (root.sinkAudio && root.pipewireReady) {
            root.sinkAudio.muted = !root.sinkAudio.muted;
            return;
        }
        Quickshell.execDetached(["sh", "-c", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"]);
    }

    tooltipHoverable: true
    tooltipText: ""
    tooltipTitle: "Volume"

    content: [
        IconLabel {
            color: root.activeColor()
            text: root.iconForVolume()
        }
    ]
    tooltipContent: Component {
        ColumnLayout {
            spacing: Config.space.md
            width: 240

            // Header Section
            RowLayout {
                Layout.fillWidth: true
                spacing: Config.space.md

                Item {
                    Layout.preferredHeight: Config.space.xxl * 2
                    Layout.preferredWidth: Config.space.xxl * 2

                    Text {
                        anchors.centerIn: parent
                        color: root.activeColor()
                        font.pixelSize: Config.type.headlineLarge.size
                        text: root.iconForVolume()
                    }
                }
                ColumnLayout {
                    spacing: Config.space.none

                    Text {
                        Layout.fillWidth: true
                        color: Config.m3.onSurface
                        elide: Text.ElideRight
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.headlineSmall.size
                        font.weight: Font.Bold
                        text: "Volume"
                    }
                    RowLayout {
                        spacing: Config.space.xs

                        Text {
                            color: Config.m3.onSurfaceVariant
                            font.family: Config.fontFamily
                            font.pixelSize: Config.type.labelMedium.size
                            text: root.volumeAvailable ? (root.muted ? "Muted" : root.volumePercent + "%") : "Unavailable"
                        }
                        Rectangle {
                            Layout.preferredHeight: boostedLabel.implicitHeight + Config.spaceHalfXs
                            Layout.preferredWidth: boostedLabel.implicitWidth + Config.space.sm
                            color: Config.m3.secondary
                            radius: Config.shape.corner.xs
                            visible: root.volumePercent > 100 && !root.muted

                            Text {
                                id: boostedLabel

                                anchors.centerIn: parent
                                color: Config.moduleBackground
                                font.family: Config.fontFamily
                                font.pixelSize: Config.type.labelSmall.size
                                font.weight: Font.Black
                                text: "BOOSTED"
                            }
                        }
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
            }

            // Details Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.xs

                Text {
                    Layout.bottomMargin: Config.space.xs
                    color: Config.m3.primary
                    font.family: Config.fontFamily
                    font.letterSpacing: 1.5
                    font.pixelSize: Config.type.labelSmall.size
                    font.weight: Font.Black
                    text: "VOLUME DETAILS"
                }
                LevelSlider {
                    Layout.fillWidth: true
                    enabled: root.volumeAvailable
                    fillColor: root.activeColor()
                    maximum: root.maxVolume
                    minimum: 0
                    value: root.sliderValue

                    onUserChanged: {
                        root.sliderValue = value;
                        root.setVolume(value);
                    }
                }
                InfoRow {
                    Layout.fillWidth: true
                    label: "Device"
                    value: root.sinkLabel()
                    visible: root.sinkLabel() !== ""
                }
            }
            TooltipActionsRow {
                spacing: Config.space.sm

                ActionChip {
                    Layout.fillWidth: true
                    active: root.muted
                    text: root.muted ? "Unmute" : "Mute"

                    onClicked: root.toggleMute()
                }
                ActionChip {
                    Layout.fillWidth: true
                    text: "50%"

                    onClicked: root.setVolume(0.5)
                }
                ActionChip {
                    Layout.fillWidth: true
                    text: "100%"

                    onClicked: root.setVolume(1.0)
                }
                ActionChip {
                    Layout.fillWidth: true
                    text: "150%"
                    visible: root.maxVolume >= 1.5

                    onClicked: root.setVolume(1.5)
                }
            }
        }
    }

    Component.onCompleted: root.refreshSink()

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }
    Connections {
        function onDefaultAudioSinkChanged() {
            root.logEvent("defaultAudioSinkChanged");
            root.refreshSink();
        }
        function onReadyChanged() {
            root.logEvent("pipewireReadyChanged");
            root.refreshSink();
        }

        target: Pipewire
    }
    Connections {
        function onReadyChanged() {
            root.logEvent("sinkReadyChanged");
            root.syncVolume();
        }

        target: root.sink
    }
    Connections {
        function onMutedChanged() {
            root.logEvent("mutedChanged");
            root.syncVolume();
        }
        function onVolumesChanged() {
            root.logEvent("volumesChanged");
            root.syncVolume();
        }

        target: root.sinkAudio
    }
    MouseArea {
        anchors.fill: parent

        onClicked: root.toggleMute()
        onWheel: function (wheel) {
            if (wheel.angleDelta.y > 0)
                root.adjustVolume(root.volumeStep);
            else if (wheel.angleDelta.y < 0)
                root.adjustVolume(-root.volumeStep);
        }
    }
}
