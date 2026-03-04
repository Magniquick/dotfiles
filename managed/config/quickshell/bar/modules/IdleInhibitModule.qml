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
    readonly property int remainingSeconds: root.computeRemainingSeconds()
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
        running: root.tooltipActive && root.inhibitEnabled && GlobalState.idleSleepInhibitUntilMs > 0 && root.visible && root.QsWindow.window && root.QsWindow.window.visible

        onTriggered: root.nowMs = Date.now()
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

            RowLayout {
                Layout.fillWidth: true
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

                    Text {
                        Layout.fillWidth: true
                        color: Config.color.on_surface
                        elide: Text.ElideRight
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.headlineSmall.size
                        font.weight: Font.Bold
                        text: "Caffeine"
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

            Text {
                Layout.fillWidth: true
                color: Config.color.on_surface_variant
                font.family: Config.fontFamily
                font.pixelSize: Config.type.labelSmall.size
                font.weight: Config.type.labelSmall.weight
                text: root.inhibitEnabled ? root.activeSubtitle() : ""
                visible: root.inhibitEnabled
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
    }

    function formatRemaining(seconds) {
        const totalSeconds = Math.max(0, Math.floor(seconds));
        const minutes = Math.floor(totalSeconds / 60);
        const hours = Math.floor(minutes / 60);
        const remMinutes = minutes % 60;

        if (hours > 0)
            return hours + "h " + remMinutes + "m";
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
    }

    Connections {
        target: GlobalState

        function onIdleSleepInhibitedChanged() {
            if (!root.tooltipActive)
                root.presetIndex = root.indexFromGlobalState();
        }
    }
}
