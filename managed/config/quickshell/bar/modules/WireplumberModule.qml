/**
 * @module WireplumberModule
 * @description Audio volume control via PipeWire/WirePlumber
 *
 * Features:
 * - Volume percentage display with tiered icons
 * - Mute toggle on click
 * - Scroll wheel volume adjustment
 * - Volume slider in tooltip (up to 200%)
 *
 * Dependencies:
 * - Quickshell.Services.Pipewire: Audio sink control
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import "../../common/materialkit" as MK
import ".."
import "../components"

ModuleContainer {
    id: root

    property bool debugLogging: false
    property bool showVirtualIo: false
    property var icons: ["", "", "", ""]
    // Input UI is normalized to 0..100, mapped onto real 0..20% gain.
    property real inputMaxVolume: 0.2
    property real maxVolume: 2.0
    property int maxVisibleAppRows: 4
    property int maxVisibleDeviceRows: 3
    property int appRowHeight: 44
    property int deviceRowHeight: 40
    property bool muted: false
    property string micMutedIcon: ""
    property string mutedIcon: ""
    readonly property int legacyPanelWidth: 240
    readonly property int panelWidth: 272
    readonly property bool pipewireReady: root.sink ? root.sink.ready : false
    readonly property var allAudioNodes: root.pipewireGloballyReady ? Pipewire.nodes : []
    readonly property var appStreams: root.collectAppStreams(root.allAudioNodes)
    readonly property var appEntries: root.buildAppEntries(root.appStreams)
    readonly property bool hasAppSection: root.appEntries.length > 0
    readonly property bool hasAudioSections: root.hasInputSection || root.hasOutputSection || root.hasAppSection || root.showVirtualIoToggle
    readonly property bool hasInputSection: root.inputDevices.length > 0
    readonly property var inputDevices: root.collectInputDevices(root.allAudioNodes)
    readonly property bool pipewireGloballyReady: Pipewire.ready
    readonly property bool hasOutputSection: root.outputDevices.length > 0
    readonly property var outputDevices: root.collectOutputDevices(root.allAudioNodes)
    readonly property bool showVirtualIoToggle: root.showVirtualIo || root.virtualInputCount > 0 || root.virtualOutputCount > 0 || root.virtualStreamCount > 0
    readonly property int virtualInputCount: root.countVirtualDevices(root.allAudioNodes, false)
    readonly property int virtualOutputCount: root.countVirtualDevices(root.allAudioNodes, true)
    readonly property int virtualStreamCount: root.countVirtualStreams(root.allAudioNodes)
    readonly property var selectedInput: Pipewire.defaultAudioSource
    readonly property var selectedOutput: Pipewire.defaultAudioSink
    property var sink: Pipewire.defaultAudioSink
    property var sinkAudio: root.sink ? root.sink.audio : null
    property real sliderValue: 0
    property bool volumeAvailable: false
    property int volumePercent: 0
    property real volumeStep: 0.01

    function activeColor() {
        return (root.muted || root.volumePercent > 100) ? Config.color.error : Config.color.secondary;
    }
    function adjustVolume(delta) {
        if (!root.sinkAudio)
            return;
        const next = Math.max(0, Math.min(root.maxVolume, root.sinkAudio.volume + delta));
        root.sinkAudio.volume = next;
    }
    function averageVolume(values) {
        let sum = 0;
        for (let i = 0; i < values.length; i++)
            sum += values[i];
        return values.length > 0 ? sum / values.length : NaN;
    }
    function nodeMaxVolume(node) {
        if (!node)
            return root.maxVolume;
        return node.isSink ? root.maxVolume : root.inputMaxVolume;
    }
    function assignNodeVolume(node, value, maxVolume) {
        const max = isFinite(maxVolume) ? maxVolume : root.nodeMaxVolume(node);
        const next = Math.max(0, Math.min(max, value));
        if (!node || !node.audio)
            return;
        node.audio.volume = next;
    }
    function adjustNodeVolumeByStep(node, directionY) {
        if (!node)
            return;
        const max = root.nodeMaxVolume(node);
        const step = max / 100;
        const delta = directionY > 0 ? step : (directionY < 0 ? -step : 0);
        if (delta === 0)
            return;
        if (!node.audio)
            return;
        root.assignNodeVolume(node, node.audio.volume + delta, max);
    }
    function adjustAppEntryVolumeByStep(entry, directionY) {
        if (!entry)
            return;
        const step = root.maxVolume / 100;
        const delta = directionY > 0 ? step : (directionY < 0 ? -step : 0);
        if (delta === 0)
            return;
        const current = Math.max(0, Math.min(root.maxVolume, entry.volume));
        root.setAppEntryVolume(entry, current + delta);
    }
    function formatVolumePercent(value, muted, maxVolume) {
        if (muted)
            return "M";
        const max = (isFinite(maxVolume) && maxVolume > 0) ? maxVolume : root.maxVolume;
        const v = isFinite(value) ? value : 0;
        const clamped = Math.max(0, Math.min(max, v));
        return Math.round(clamped * 100).toString();
    }
    function buildAppEntries(nativeStreams) {
        const entries = [];
        for (let i = 0; i < nativeStreams.length; i++) {
            const item = nativeStreams[i];
            if (!item)
                continue;
            const rawPid = item.properties ? item.properties["application.process.id"] : undefined;
            entries.push({
                node: item,
                id: root.nodeId(item),
                label: root.nodeLabel(item, "Unknown App"),
                muted: !!(item.audio && item.audio.muted),
                volume: item.audio ? item.audio.volume : 0,
                enabled: !!item.audio,
                pid: rawPid !== undefined ? Number(rawPid) : -1
            });
        }
        return entries;
    }
    function collectAppStreams(nodes) {
        const result = [];
        const n = root.modelCount(nodes);
        if (n === 0)
            return result;

        for (let i = 0; i < n; i++) {
            const node = root.modelAt(nodes, i);
            if (!node || !node.isStream)
                continue;
            if (!root.showVirtualIo && root.isVirtualIoNode(node))
                continue;
            result.push(node);
        }
        return root.sortNodes(result, null);
    }
    function countAudioStreams(nodes, requireAudio) {
        const n = root.modelCount(nodes);
        if (n === 0)
            return 0;
        let total = 0;
        for (let i = 0; i < n; i++) {
            const node = root.modelAt(nodes, i);
            if (!node || !node.isStream)
                continue;
            if (requireAudio && !node.audio)
                continue;
            total++;
        }
        return total;
    }
    function collectInputDevices(nodes) {
        const result = [];
        const n = root.modelCount(nodes);
        if (n === 0)
            return result;

        for (let i = 0; i < n; i++) {
            const node = root.modelAt(nodes, i);
            if (!node || !node.audio || node.isStream || node.isSink)
                continue;
            if (!root.showVirtualIo && root.isVirtualIoNode(node))
                continue;
            result.push(node);
        }
        return root.sortNodes(result, root.selectedInput);
    }
    function collectOutputDevices(nodes) {
        const result = [];
        const n = root.modelCount(nodes);
        if (n === 0)
            return result;

        for (let i = 0; i < n; i++) {
            const node = root.modelAt(nodes, i);
            if (!node || !node.audio || node.isStream || !node.isSink)
                continue;
            if (!root.showVirtualIo && root.isVirtualIoNode(node))
                continue;
            result.push(node);
        }
        return root.sortNodes(result, root.selectedOutput);
    }
    function countVirtualDevices(nodes, sinkDevices) {
        const n = root.modelCount(nodes);
        if (n === 0)
            return 0;

        let total = 0;
        for (let i = 0; i < n; i++) {
            const node = root.modelAt(nodes, i);
            if (!node || !node.audio || node.isStream)
                continue;
            if (!!node.isSink !== !!sinkDevices)
                continue;
            if (!root.isVirtualIoNode(node))
                continue;
            total++;
        }
        return total;
    }
    function countVirtualStreams(nodes) {
        const n = root.modelCount(nodes);
        if (n === 0)
            return 0;

        let total = 0;
        for (let i = 0; i < n; i++) {
            const node = root.modelAt(nodes, i);
            if (!node || !node.isStream)
                continue;
            if (!root.isVirtualIoNode(node))
                continue;
            total++;
        }
        return total;
    }
    function deviceIsActive(node, selectedNode) {
        const selectedId = root.nodeId(selectedNode);
        const nodeId = root.nodeId(node);
        if (selectedId < 0 || nodeId < 0)
            return false;
        return selectedId === nodeId;
    }
    function deviceTypeIcon(node, inputSection) {
        if (inputSection)
            return "";
        if (root.deviceIsActive(node, root.selectedOutput))
            return root.iconForVolume();
        return "";
    }
    function appEntryLabel(entry) {
        if (!entry)
            return "";
        if (entry.label !== undefined && entry.label !== null)
            return String(entry.label).trim();
        if (entry.name !== undefined && entry.name !== null)
            return String(entry.name).trim();
        return "";
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
    function nodeId(node) {
        if (!node || node.id === undefined || node.id === null)
            return -1;
        const id = Number(node.id);
        return isFinite(id) ? id : -1;
    }
    function nodeLabel(node, fallback) {
        if (node && node.description && node.description !== "")
            return String(node.description);
        if (node && node.name && node.name !== "")
            return String(node.name);
        return fallback;
    }
    function nodeTypeString(node) {
        if (!node || node.type === undefined || node.type === null)
            return "";
        try {
            return String(PwNodeType.toString(node.type) || "").toLowerCase();
        } catch (err) {
            return String(node.type || "").toLowerCase();
        }
    }
    function isVirtualIoNode(node) {
        const typeText = root.nodeTypeString(node);
        const label = root.nodeLabel(node, "").toLowerCase();
        const name = node && node.name ? String(node.name).toLowerCase() : "";
        const combined = (label + " " + name).trim();

        if (typeText.indexOf("filter") !== -1 || typeText.indexOf("virtual") !== -1)
            return true;

        return root.isVirtualIoLabel(combined);
    }
    function isVirtualIoLabel(text) {
        const combined = String(text || "").toLowerCase();

        const virtualKeywords = [
            "monitor",
            "loopback",
            "virtual",
            "null",
            "dummy",
            "audiorelay",
            "echo-cancel",
            "simultaneous"
        ];

        for (let i = 0; i < virtualKeywords.length; i++) {
            if (combined.indexOf(virtualKeywords[i]) !== -1)
                return true;
        }
        return false;
    }
    function modelAt(model, index) {
        if (!model || index < 0)
            return null;
        if (model.values && typeof model.values.length === "number")
            return model.values[index];
        if (typeof model.get === "function")
            return model.get(index);
        return model[index];
    }
    function modelCount(model) {
        if (!model)
            return 0;
        if (model.values && typeof model.values.length === "number")
            return model.values.length;
        if (typeof model.count === "number")
            return model.count;
        if (typeof model.length === "number")
            return model.length;
        return 0;
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
        if (!root.sinkAudio || !root.pipewireReady)
            return;
        root.sinkAudio.volume = next;
    }
    function setPreferredInput(node) {
        if (!node)
            return;
        Pipewire.preferredDefaultAudioSource = node;
    }
    function setPreferredOutput(node) {
        if (!node)
            return;
        Pipewire.preferredDefaultAudioSink = node;
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
    function sortNodes(nodes, activeNode) {
        const selectedId = root.nodeId(activeNode);
        const sorted = nodes.slice();
        sorted.sort(function(a, b) {
            const aId = root.nodeId(a);
            const bId = root.nodeId(b);
            const aActive = selectedId >= 0 && aId === selectedId;
            const bActive = selectedId >= 0 && bId === selectedId;
            if (aActive !== bActive)
                return aActive ? -1 : 1;

            const aName = root.nodeLabel(a, "").toLowerCase();
            const bName = root.nodeLabel(b, "").toLowerCase();
            if (aName < bName)
                return -1;
            if (aName > bName)
                return 1;
            return aId - bId;
        });
        return sorted;
    }
    function setAppEntryVolume(entry, value) {
        if (!entry || !entry.node)
            return;
        root.assignNodeVolume(entry.node, value);
    }
    function toggleAppEntryMute(entry) {
        if (!entry || !entry.node)
            return;
        root.toggleNodeMute(entry.node);
    }
    function toggleNodeMute(node) {
        if (!node || !node.audio)
            return;
        node.audio.muted = !node.audio.muted;
    }
    function raiseAppEntry(entry) {
        if (!entry || !(entry.pid > 0))
            return;
        Hyprland.dispatch("focuswindow pid:" + entry.pid);
    }
    function toggleMute() {
        if (!root.sinkAudio || !root.pipewireReady)
            return;
        root.sinkAudio.muted = !root.sinkAudio.muted;
    }

    tooltipHoverable: true
    tooltipText: ""
    tooltipTitle: root.hasAudioSections ? "Audio" : "Volume"

    content: [
        IconLabel {
            color: root.activeColor()
            text: root.iconForVolume()
        }
    ]
    Component {
        id: deviceRowDelegate

        Rectangle {
            required property var modelData

            readonly property bool _isInput: ListView.view ? ListView.view.isInput : false
            readonly property bool active: root.deviceIsActive(modelData, _isInput ? root.selectedInput : root.selectedOutput)
            readonly property bool nodeMuted: !!(modelData && modelData.audio && modelData.audio.muted)
            readonly property real nodeVolume: modelData && modelData.audio ? modelData.audio.volume : 0
            readonly property real nodeMax: root.nodeMaxVolume(modelData)

            width: ListView.view.width
            height: root.deviceRowHeight
            radius: Config.shape.corner.md
            color: rowMouseArea.containsMouse ? Qt.alpha(Config.color.surface_variant, 0.5) : (active ? Qt.alpha(Config.color.primary_container, 0.45) : Config.color.surface_container_high)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Config.space.sm
                anchors.rightMargin: Config.space.sm
                spacing: Config.space.sm

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: 28
                    Layout.preferredWidth: 28
                    color: active ? Qt.alpha(Config.color.primary, 0.75) : Config.color.surface_variant
                    radius: width / 2

                    Text {
                        anchors.centerIn: parent
                        color: Config.color.on_surface
                        font.family: Config.iconFontFamily
                        font.pixelSize: Config.type.labelLarge.size
                        text: _isInput ? (nodeMuted ? root.micMutedIcon : root.deviceTypeIcon(modelData, true)) : root.deviceTypeIcon(modelData, false)
                    }
                }
                Text {
                    Layout.fillWidth: true
                    color: active ? Config.color.on_primary_container : Config.color.on_surface
                    elide: Text.ElideRight
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.bodyLarge.size
                    font.weight: Config.type.bodyLarge.weight
                    text: root.nodeLabel(modelData, _isInput ? "Unknown Input" : "Unknown Output")
                }
                Item {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: 26
                    Layout.preferredWidth: 26

                    MK.CircleProgressBar {
                        anchors.fill: parent
                        enabled: root.pipewireGloballyReady
                        from: 0
                        to: nodeMax
                        value: nodeVolume
                    }

                    Text {
                        anchors.centerIn: parent
                        color: active ? Config.color.on_primary_container : Config.color.on_surface
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.labelSmall.size
                        font.weight: Font.Bold
                        text: root.formatVolumePercent(nodeVolume, nodeMuted, nodeMax)
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.pipewireGloballyReady
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor

                        onClicked: function() {
                            root.toggleNodeMute(modelData);
                        }
                        onWheel: function(wheel) {
                            root.adjustNodeVolumeByStep(modelData, wheel.angleDelta.y);
                            wheel.accepted = true;
                        }
                    }
                }
            }

            MK.HybridRipple {
                anchors.fill: parent
                color: active ? Config.color.on_primary_container : Config.color.on_surface
                pressX: rowMouseArea.pressX
                pressY: rowMouseArea.pressY
                pressed: rowMouseArea.pressed
                radius: parent.radius
                stateLayerEnabled: false
                stateOpacity: 0
            }
            MouseArea {
                id: rowMouseArea

                property real pressX: width / 2
                property real pressY: height / 2

                anchors.fill: parent
                enabled: root.pipewireGloballyReady
                hoverEnabled: true
                onClicked: function(mouse) {
                    if (!modelData)
                        return;
                    if (mouse.button === Qt.RightButton) {
                        root.toggleNodeMute(modelData);
                        return;
                    }
                    if (mouse.button === Qt.LeftButton) {
                        if (_isInput)
                            root.setPreferredInput(modelData);
                        else
                            root.setPreferredOutput(modelData);
                    }
                }
                onPressed: function(mouse) {
                    pressX = mouse.x;
                    pressY = mouse.y;
                }
                onWheel: function(wheel) {
                    root.adjustNodeVolumeByStep(modelData, wheel.angleDelta.y);
                    wheel.accepted = true;
                }
            }
        }
    }
    tooltipContent: Component {
        ColumnLayout {
            spacing: Config.space.sm
            width: root.hasAudioSections ? root.panelWidth : root.legacyPanelWidth

            TooltipHeader {
                icon: root.iconForVolume()
                iconColor: root.activeColor()
                subtitle: root.volumeAvailable ? (root.muted ? "Muted" : root.volumePercent + "%") : "Unavailable"
                title: "Volume"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Config.space.none
                visible: root.volumePercent > 100 && !root.muted

                Item {
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.preferredHeight: boostedLabel.implicitHeight + Config.spaceHalfXs
                    Layout.preferredWidth: boostedLabel.implicitWidth + Config.space.sm
                    color: Config.color.secondary
                    radius: Config.shape.corner.xs

                    Text {
                        id: boostedLabel

                        anchors.centerIn: parent
                        color: Config.color.surface_container
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.labelSmall.size
                        font.weight: Font.Black
                        text: "BOOSTED"
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.xs
                visible: root.hasOutputSection

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Config.space.sm

                    SectionHeader {
                        text: "OUTPUT"
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    ActionChip {
                        Layout.alignment: Qt.AlignVCenter
                        active: root.showVirtualIo
                        visible: root.showVirtualIoToggle
                        text: "Virtual I/O " + (root.virtualInputCount + root.virtualOutputCount + root.virtualStreamCount).toString()
                        onClicked: root.showVirtualIo = !root.showVirtualIo
                    }
                }
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(root.maxVisibleDeviceRows, root.outputDevices.length) * root.deviceRowHeight

                    ListView {
                        property bool isInput: false

                        anchors.fill: parent
                        clip: true
                        interactive: count > root.maxVisibleDeviceRows
                        model: root.outputDevices
                        spacing: Config.space.xs
                        delegate: deviceRowDelegate
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.xs
                visible: root.hasInputSection

                SectionHeader {
                    text: "INPUT"
                }
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(root.maxVisibleDeviceRows, root.inputDevices.length) * root.deviceRowHeight

                    ListView {
                        property bool isInput: true

                        anchors.fill: parent
                        clip: true
                        interactive: count > root.maxVisibleDeviceRows
                        model: root.inputDevices
                        spacing: Config.space.xs
                        delegate: deviceRowDelegate
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Config.color.outline_variant
                opacity: 0.9
                visible: (root.hasInputSection || root.hasOutputSection) && root.hasAppSection
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.xs
                visible: root.hasAppSection

                SectionHeader {
                    text: "APPLICATIONS"
                }
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(root.maxVisibleAppRows, root.appEntries.length) * root.appRowHeight

                    ListView {
                        anchors.fill: parent
                        clip: true
                        interactive: count > root.maxVisibleAppRows
                        model: root.appEntries
                        spacing: Config.space.xs

                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool appMuted: !!modelData.muted
                            readonly property bool enabledRow: !!modelData.enabled
                            readonly property string delegateLabel: root.appEntryLabel(modelData)

                            width: ListView.view.width
                            height: root.appRowHeight
                            radius: Config.shape.corner.md
                            color: appRowHoverArea.containsMouse ? Qt.alpha(Config.color.surface_variant, 0.55) : Config.color.surface_container_high
                            opacity: enabledRow ? 1 : 0.55

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Config.space.sm
                                anchors.rightMargin: Config.space.sm
                                spacing: Config.space.sm

                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.preferredHeight: 24
                                    Layout.preferredWidth: 24
                                    color: Config.color.surface_variant
                                    radius: Config.shape.corner.sm

                                    Text {
                                        anchors.centerIn: parent
                                        color: Config.color.on_surface
                                        font.family: Config.fontFamily
                                        font.pixelSize: Config.type.labelSmall.size
                                        font.weight: Font.Bold
                                        text: {
                                            const label = String(appNameText.text || "").trim();
                                            return label.length > 0 ? label.charAt(0).toUpperCase() : "?";
                                        }
                                    }
                                }
                                Text {
                                    id: appNameText

                                    Layout.fillWidth: true
                                    color: Config.color.on_surface
                                    elide: Text.ElideRight
                                    font.family: Config.fontFamily
                                    font.pixelSize: Config.type.bodyMedium.size
                                    font.weight: Config.type.bodyMedium.weight
                                    text: delegateLabel
                                }
                                Item {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.preferredHeight: 26
                                    Layout.preferredWidth: 26

                                    MK.CircleProgressBar {
                                        id: appVolumeCircle

                                        anchors.fill: parent
                                        enabled: enabledRow
                                        from: 0
                                        to: root.maxVolume
                                        value: enabledRow ? modelData.volume : 0
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        color: Config.color.on_surface
                                        font.family: Config.fontFamily
                                        font.pixelSize: Config.type.labelSmall.size
                                        font.weight: Font.Bold
                                        text: appMuted ? "M" : Math.round(Math.max(0, Math.min(root.maxVolume, appVolumeCircle.value)) * 100).toString()
                                    }

                                    MouseArea {
                                        id: appCircleArea

                                        anchors.fill: parent
                                        enabled: enabledRow
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: Qt.PointingHandCursor

                                        onClicked: function() {
                                            root.toggleAppEntryMute(modelData);
                                        }
                                        onWheel: function(wheel) {
                                            root.adjustAppEntryVolumeByStep(modelData, wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y);
                                            wheel.accepted = true;
                                        }
                                    }
                                }
                            }

                            MK.HybridRipple {
                                anchors.fill: parent
                                color: Config.color.on_surface
                                pressX: appRowHoverArea.pressX
                                pressY: appRowHoverArea.pressY
                                pressed: appRowHoverArea.pressed
                                radius: parent.radius
                                stateLayerEnabled: false
                                stateOpacity: 0
                            }
                            MouseArea {
                                id: appRowHoverArea

                                property real pressX: width / 2
                                property real pressY: height / 2

                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true

                                onClicked: root.raiseAppEntry(modelData)
                                onPressed: function(mouse) {
                                    pressX = mouse.x;
                                    pressY = mouse.y;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        root.refreshSink();
    }

    PwObjectTracker {
        objects: (function() {
            const objects = [];
            const seenIds = {};
            const addNode = function(node) {
                if (!node)
                    return;
                const id = root.nodeId(node);
                if (id >= 0) {
                    const key = String(id);
                    if (seenIds[key])
                        return;
                    seenIds[key] = true;
                } else if (objects.indexOf(node) !== -1) {
                    return;
                }
                objects.push(node);
            };

            addNode(root.sink);
            addNode(root.selectedInput);
            addNode(root.selectedOutput);
            const allNodesCount = root.modelCount(root.allAudioNodes);
            for (let i = 0; i < allNodesCount; i++)
                addNode(root.modelAt(root.allAudioNodes, i));
            for (let i = 0; i < root.inputDevices.length; i++)
                addNode(root.inputDevices[i]);
            for (let i = 0; i < root.outputDevices.length; i++)
                addNode(root.outputDevices[i]);
            for (let i = 0; i < root.appStreams.length; i++)
                addNode(root.appStreams[i]);

            return objects;
        })()
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
                root.adjustVolume(-root.volumeStep);
            else if (wheel.angleDelta.y < 0)
                root.adjustVolume(root.volumeStep);
        }
    }
}
