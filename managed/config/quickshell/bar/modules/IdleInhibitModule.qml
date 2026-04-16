/**
 * @module IdleInhibitModule
 * @description Toggle idle inhibition for the bar window.
 *
 * Usage:
 * IdleInhibitModule { targetWindow: parentWindow }
 */
pragma ComponentBehavior: Bound
import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import "../../common/materialkit" as MK

ModuleContainer {
    id: root
    // TODO: Improve Caffeine module UX/content states and align behavior with other system modules.

    property bool inhibitEnabled: GlobalState.idleSleepInhibited
    property int presetIndex: root.indexFromGlobalState()
    property var targetWindow: null
    property double nowMs: Date.now()
    property var activeIdleInhibitors: []
    property int portalInhibitSessionCount: 0
    readonly property int remainingSeconds: root.computeRemainingSeconds()
    readonly property int dpmsTimeoutSeconds: Math.max(0, Math.round(GlobalState.idleMonitorSleepTimeoutSec || 0))
    readonly property int earliestDpmsSeconds: root.computeEarliestDpmsSeconds()
    property bool detailsExpanded: false
    readonly property var displayOffPresets: [0, 60, 120, 180, 300, 600, 900, 1800]
    readonly property var sleepPresets: [0, 900, 1800, 3600, 7200]
    property int displayOffIndex: root.displayOffIndexFromState()
    property int sleepIndex: root.sleepIndexFromState()
    readonly property string iconText: root.inhibitEnabled ? "" : "󰒲"
    readonly property color iconColor: root.inhibitEnabled ? Config.color.on_primary_container : Config.color.on_surface_variant

    backgroundColor: root.inhibitEnabled ? Config.color.primary_container : Config.barModuleBackground
    tooltipHoverable: true
    tooltipTitle: "Caffeine"
    tooltipText: ""
    tooltipSubtitle: ""

    onClicked: {
        if (root.inhibitEnabled)
            GlobalState.clearSleepInhibit();
        else
            GlobalState.setSleepInhibitIndefinite();
    }

    IdleInhibitor {
        enabled: GlobalState.idleSleepInhibited
        window: root.targetWindow
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.tooltipActive && root.inhibitEnabled && GlobalState.idleSleepInhibitUntilMs > 0 && root.visible

        onTriggered: root.nowMs = Date.now()
    }

    CommandRunner {
        enabled: root.tooltipActive && root.visible
        intervalMs: 3000
        command: ["systemd-inhibit", "--list"]
        timeoutMs: 3000

        onRan: function(output) {
            root.activeIdleInhibitors = root.parseSystemdIdleInhibitors(output);
        }

        onError: function() {
            root.activeIdleInhibitors = [];
        }

        onTimeout: root.activeIdleInhibitors = []
    }

    CommandRunner {
        enabled: root.tooltipActive && root.visible
        intervalMs: 3000
        command: ["busctl", "--user", "tree", "org.freedesktop.portal.Desktop"]
        timeoutMs: 3000

        onRan: function(output) {
            root.portalInhibitSessionCount = root.parsePortalSessionCount(output);
        }

        onError: function() {
            root.portalInhibitSessionCount = 0;
        }

        onTimeout: root.portalInhibitSessionCount = 0
    }

    content: [
        IconLabel {
            color: root.iconColor
            text: root.iconText
        }
    ]

    tooltipContent: Component {
        ColumnLayout {
            spacing: Config.space.sm

            // Header — clickable to toggle details
            Item {
                Layout.fillWidth: true
                implicitHeight: caffeineHeader.implicitHeight

                RowLayout {
                    id: caffeineHeader

                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: Config.space.md

                    Item {
                        Layout.preferredHeight: Config.space.xxl * 2
                        Layout.preferredWidth: Config.space.xxl * 2

                        Rectangle {
                            anchors.centerIn: parent
                            color: Qt.alpha(root.inhibitEnabled ? Config.color.primary : Config.color.on_surface_variant, 0.12)
                            height: parent.height
                            radius: height / 2
                            width: parent.width
                        }

                        Text {
                            anchors.centerIn: parent
                            color: root.inhibitEnabled ? Config.color.primary : Config.color.on_surface_variant
                            font.family: Config.iconFontFamily
                            font.pixelSize: Config.type.headlineLarge.size
                            text: root.iconText
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Config.space.none

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Config.space.xs

                            Text {
                                Layout.minimumWidth: 0
                                color: Config.color.on_surface
                                elide: Text.ElideRight
                                font.family: Config.fontFamily
                                font.pixelSize: Config.type.headlineSmall.size
                                font.weight: Font.Bold
                                text: "Caffeine"
                            }

                            Text {
                                color: Config.color.on_surface_variant
                                font.family: Config.iconFontFamily
                                font.pixelSize: Config.type.labelLarge.size
                                text: root.detailsExpanded ? "󰅀" : "󰅂"
                            }

                            Item { Layout.fillWidth: true }
                        }

                        Text {
                            Layout.fillWidth: true
                            color: Config.color.on_surface_variant
                            elide: Text.ElideRight
                            font.family: Config.fontFamily
                            font.pixelSize: Config.type.labelMedium.size
                            text: root.inhibitEnabled ? "Awake mode enabled" : "Auto sleep enabled"
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.detailsExpanded = !root.detailsExpanded
                }
            }

            // Screen 0: Quick controls
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.sm
                visible: !root.detailsExpanded

                Text {
                    Layout.fillWidth: true
                    color: Config.color.on_surface_variant
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.labelSmall.size
                    font.weight: Config.type.labelSmall.weight
                    text: root.inhibitEnabled
                        ? root.activeSubtitle()
                        : root.dpmsTimeoutSeconds > 0
                            ? "Display off after " + root.timeoutLabel(root.dpmsTimeoutSeconds) + " idle"
                            : "Display idle timeout disabled"
                    wrapMode: Text.WordWrap
                }

                MK.DiscreteSlider {
                    id: presetSlider

                    Layout.fillWidth: true
                    fillColor: Config.color.primary
                    handleColor: Config.color.primary
                    handleSize: 12
                    maximum: 4
                    minimum: 0
                    steps: 5
                    tickColor: Config.color.on_primary
                    tickInactiveColor: Config.color.on_surface_variant
                    trackColor: Qt.alpha(Config.color.surface_variant, 0.9)
                    trackThickness: 2
                    value: root.presetIndex

                    onUserChanged: function(value) {
                        const nextIndex = Math.max(0, Math.min(4, Math.round(value)));
                        if (nextIndex === root.presetIndex)
                            return;

                        root.presetIndex = nextIndex;
                        root.applyPreset(nextIndex);
                    }
                }
            }

            // Screen 1: Timeout settings
            ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Config.space.xs
                    visible: root.detailsExpanded

                    // Display Off section
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: Config.space.xs
                        spacing: Config.space.sm

                        Text {
                            color: Config.color.primary
                            font.family: Config.fontFamily
                            font.letterSpacing: 1.5
                            font.pixelSize: Config.type.labelSmall.size
                            font.weight: Font.Black
                            text: "DISPLAY OFF"
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            color: Qt.alpha(Config.color.outline_variant, 0.55)
                            implicitHeight: 1
                            radius: 1
                        }

                        Text {
                            color: Config.color.on_surface
                            font.family: Config.fontFamily
                            font.pixelSize: Config.type.labelSmall.size
                            font.weight: Font.Medium
                            text: root.timeoutLabel(GlobalState.idleMonitorSleepTimeoutSec)
                        }
                    }

                    MK.DiscreteSlider {
                        Layout.fillWidth: true
                        fillColor: Config.color.secondary
                        handleColor: Config.color.secondary
                        handleSize: 12
                        maximum: root.displayOffPresets.length - 1
                        minimum: 0
                        steps: root.displayOffPresets.length
                        tickColor: Config.color.on_secondary
                        tickInactiveColor: Config.color.on_surface_variant
                        trackColor: Qt.alpha(Config.color.surface_variant, 0.9)
                        trackThickness: 2
                        value: root.displayOffIndex

                        onUserChanged: function(value) {
                            const nextIndex = Math.max(0, Math.min(root.displayOffPresets.length - 1, Math.round(value)));
                            if (nextIndex === root.displayOffIndex)
                                return;
                            root.displayOffIndex = nextIndex;
                            root.applyDisplayOff(nextIndex);
                        }
                    }

                    // Suspend section
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Config.space.sm
                        Layout.bottomMargin: Config.space.xs
                        spacing: Config.space.sm

                        Text {
                            color: Config.color.primary
                            font.family: Config.fontFamily
                            font.letterSpacing: 1.5
                            font.pixelSize: Config.type.labelSmall.size
                            font.weight: Font.Black
                            text: "SUSPEND"
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            color: Qt.alpha(Config.color.outline_variant, 0.55)
                            implicitHeight: 1
                            radius: 1
                        }

                        Text {
                            color: Config.color.on_surface
                            font.family: Config.fontFamily
                            font.pixelSize: Config.type.labelSmall.size
                            font.weight: Font.Medium
                            text: root.timeoutLabel(GlobalState.idleSuspendEnabled ? Math.round(GlobalState.idleSuspendTimeoutSec) : 0)
                        }
                    }

                    MK.DiscreteSlider {
                        Layout.fillWidth: true
                        fillColor: Config.color.tertiary
                        handleColor: Config.color.tertiary
                        handleSize: 12
                        maximum: root.sleepPresets.length - 1
                        minimum: 0
                        steps: root.sleepPresets.length
                        tickColor: Config.color.on_tertiary
                        tickInactiveColor: Config.color.on_surface_variant
                        trackColor: Qt.alpha(Config.color.surface_variant, 0.9)
                        trackThickness: 2
                        value: root.sleepIndex

                        onUserChanged: function(value) {
                            const nextIndex = Math.max(0, Math.min(root.sleepPresets.length - 1, Math.round(value)));
                            if (nextIndex === root.sleepIndex)
                                return;
                            root.sleepIndex = nextIndex;
                            root.applySleep(nextIndex);
                        }
                    }

                    // Status section
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Config.space.sm
                        Layout.bottomMargin: Config.space.xs
                        spacing: Config.space.sm

                        Text {
                            color: Config.color.primary
                            font.family: Config.fontFamily
                            font.letterSpacing: 1.5
                            font.pixelSize: Config.type.labelSmall.size
                            font.weight: Font.Black
                            text: "STATUS"
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            color: Qt.alpha(Config.color.outline_variant, 0.55)
                            implicitHeight: 1
                            radius: 1
                        }
                    }

                    InfoRow {
                        Layout.fillWidth: true
                        label: "Inhibitors"
                        value: root.activeIdleInhibitors.length > 0 ? root.activeIdleInhibitors.join(", ") : "None"
                    }

                    InfoRow {
                        Layout.fillWidth: true
                        label: "Portal sessions"
                        value: root.portalInhibitSessionCount.toString()
                    }
            }
        }
    }

    function timeoutLabel(seconds) {
        const sec = Math.max(0, Math.round(seconds));
        if (sec <= 0)
            return "Never";
        if (sec < 60)
            return sec + "s";
        const minutes = Math.floor(sec / 60);
        const hours = Math.floor(minutes / 60);
        if (hours > 0) {
            const rem = minutes % 60;
            return rem > 0 ? hours + "h " + rem + "m" : hours + "h";
        }
        return minutes + "m";
    }

    function findClosestIndex(presets, value) {
        let best = 0;
        let bestDiff = Math.abs(presets[0] - value);
        for (let i = 1; i < presets.length; i++) {
            const diff = Math.abs(presets[i] - value);
            if (diff < bestDiff) {
                bestDiff = diff;
                best = i;
            }
        }
        return best;
    }

    function displayOffIndexFromState() {
        return root.findClosestIndex(root.displayOffPresets, GlobalState.idleMonitorSleepTimeoutSec);
    }

    function sleepIndexFromState() {
        if (!GlobalState.idleSuspendEnabled)
            return 0;
        return root.findClosestIndex(root.sleepPresets, Math.round(GlobalState.idleSuspendTimeoutSec));
    }

    function applyDisplayOff(index) {
        const i = Math.max(0, Math.min(index, root.displayOffPresets.length - 1));
        GlobalState.idleMonitorSleepTimeoutSec = root.displayOffPresets[i];
    }

    function applySleep(index) {
        const i = Math.max(0, Math.min(index, root.sleepPresets.length - 1));
        const seconds = root.sleepPresets[i];
        if (seconds <= 0) {
            GlobalState.idleSuspendEnabled = false;
        } else {
            GlobalState.idleSuspendEnabled = true;
            GlobalState.idleSuspendTimeoutSec = seconds;
        }
    }

    function formatRemaining(seconds) {
        const totalSeconds = Math.max(0, Math.floor(seconds));
        const minutes = Math.floor(totalSeconds / 60);
        const hours = Math.floor(minutes / 60);
        const remMinutes = minutes % 60;
        const remSeconds = totalSeconds % 60;

        if (hours > 0)
            return hours + "h " + remMinutes + "m";
        if (minutes > 0)
            return minutes + "m";
        if (totalSeconds > 0)
            return remSeconds + "s";
        return minutes + "m";
    }

    function activeSubtitle() {
        if (GlobalState.idleSleepInhibitModeMinutes === -1 || GlobalState.idleSleepInhibitUntilMs <= 0)
            return "Preventing idle sleep until turned off";

        return "Preventing idle sleep for " + root.formatRemaining(root.remainingSeconds);
    }

    function computeRemainingSeconds() {
        if (!root.inhibitEnabled || GlobalState.idleSleepInhibitUntilMs <= 0)
            return 0;
        return Math.max(0, Math.floor((GlobalState.idleSleepInhibitUntilMs - root.nowMs) / 1000));
    }

    function computeEarliestDpmsSeconds() {
        if (!(root.dpmsTimeoutSeconds > 0))
            return 0;

        if (!root.inhibitEnabled)
            return root.dpmsTimeoutSeconds;

        if (GlobalState.idleSleepInhibitUntilMs > 0)
            return root.remainingSeconds + root.dpmsTimeoutSeconds;

        return 0;
    }

    function parseSystemdIdleInhibitors(output) {
        const names = [];
        const seen = {};
        const lines = String(output || "").split("\n");

        for (const rawLine of lines) {
            const line = rawLine.trim();
            if (line === "" || line.indexOf("WHO") === 0 || line.indexOf("inhibitors listed.") !== -1)
                continue;

            const match = rawLine.match(/^\s*(.+?)\s+\d+\s+\S+\s+\d+\s+\S+\s+(\S+)\s+(.+?)\s+(block|delay)\s*$/);
            if (!match)
                continue;

            const who = match[1].trim();
            const what = match[2].trim().toLowerCase();
            if (what.split(":").indexOf("idle") === -1)
                continue;

            if (!seen[who]) {
                seen[who] = true;
                names.push(who);
            }
        }

        return names;
    }

    function parsePortalSessionCount(output) {
        const lines = String(output || "").split("\n");
        let count = 0;

        for (const rawLine of lines) {
            const line = rawLine.trim();
            if (line.indexOf("/org/freedesktop/portal/desktop/session/") === -1)
                continue;
            if (line === "/org/freedesktop/portal/desktop/session")
                continue;
            count += 1;
        }

        return count;
    }

    function dpmsSummary() {
        if (!(root.dpmsTimeoutSeconds > 0))
            return "DPMS off is disabled";

        const totalLabel = root.formatRemaining(root.dpmsTimeoutSeconds);
        if (!root.inhibitEnabled)
            return "Displays turn off after " + totalLabel + " of idle time";

        if (GlobalState.idleSleepInhibitUntilMs > 0)
            return "DPMS off in " + root.formatRemaining(root.earliestDpmsSeconds) + " total (" + root.formatRemaining(root.remainingSeconds) + " inhibit remaining + " + totalLabel + " DPMS timeout)";

        return "DPMS timeout is " + totalLabel + " after caffeine is turned off";
    }

    function inhibitorSummary() {
        const parts = [];

        if (root.activeIdleInhibitors.length > 0)
            parts.push("systemd idle inhibitors: " + root.activeIdleInhibitors.join(", "));

        if (root.portalInhibitSessionCount > 0)
            parts.push("portal inhibit sessions: " + root.portalInhibitSessionCount);

        if (parts.length === 0)
            return "Active inhibitors: none detected";

        return "Active inhibitors: " + parts.join(" | ");
    }

    function indexFromGlobalState() {
        if (!GlobalState.idleSleepInhibited)
            return 0;
        if (GlobalState.idleSleepInhibitModeMinutes === 15)
            return 1;
        if (GlobalState.idleSleepInhibitModeMinutes === 60)
            return 2;
        if (GlobalState.idleSleepInhibitModeMinutes === 120)
            return 3;
        return 4;
    }

    function labelForIndex(index) {
        if (index <= 0)
            return "Off";
        if (index === 1)
            return "15m";
        if (index === 2)
            return "1h";
        if (index === 3)
            return "2h";
        return "Until Off";
    }

    function applyPreset(index) {
        if (index <= 0) {
            GlobalState.clearSleepInhibit();
            return;
        }
        if (index === 1) {
            GlobalState.setSleepInhibitForMinutes(15);
            return;
        }
        if (index === 2) {
            GlobalState.setSleepInhibitForMinutes(60);
            return;
        }
        if (index === 3) {
            GlobalState.setSleepInhibitForMinutes(120);
            return;
        }
        GlobalState.setSleepInhibitIndefinite();
    }

    onTooltipActiveChanged: {
        if (root.tooltipActive) {
            root.nowMs = Date.now();
            root.presetIndex = root.indexFromGlobalState();
            root.displayOffIndex = root.displayOffIndexFromState();
            root.sleepIndex = root.sleepIndexFromState();
        }
    }

    Connections {
        enabled: root.tooltipActive
        target: GlobalState

        function onIdleSleepInhibitedChanged() {
            root.presetIndex = root.indexFromGlobalState();
        }

        function onIdleSleepInhibitModeMinutesChanged() {
            root.presetIndex = root.indexFromGlobalState();
        }

        function onIdleSleepInhibitUntilMsChanged() {
            root.nowMs = Date.now();
            root.presetIndex = root.indexFromGlobalState();
        }

        function onIdleMonitorSleepTimeoutSecChanged() {
            root.nowMs = Date.now();
            root.displayOffIndex = root.displayOffIndexFromState();
        }

        function onIdleSuspendEnabledChanged() {
            root.sleepIndex = root.sleepIndexFromState();
        }

        function onIdleSuspendTimeoutSecChanged() {
            root.sleepIndex = root.sleepIndexFromState();
        }
    }

    Connections {
        target: GlobalState

        function onIdleSleepInhibitedChanged() {
            if (!root.tooltipActive)
                root.presetIndex = root.indexFromGlobalState();
        }
    }
}
