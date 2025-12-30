import ".."
import "../components"
import "../components/JsonUtils.js" as JsonUtils
import QtQuick
import QtQuick.Layouts
import Quickshell

ModuleContainer {
    id: root

    property bool cameraActive: false
    property string cameraApps: ""
    property color cameraColor: Config.m3.warning
    property string cameraIcon: ""
    property bool locationActive: false
    property string locationApps: ""
    property color locationColor: Config.m3.tertiary
    property string locationIcon: ""
    property bool micActive: false
    property string micApps: ""
    property color micColor: Config.m3.success
    property string micIcon: ""
    property bool screenActive: false
    property string screenApps: ""
    property color screenColor: Config.m3.primary
    property string screenIcon: "󰍹"
    readonly property string scriptPath: Quickshell.shellPath(((Quickshell.shellDir || "").endsWith("/bar") ? "" : "bar/") + "modules/privacy/privacy_dots.sh")
    property string statusTooltip: "Privacy: idle"

    function appLabel(apps) {
        if (!apps || apps.trim() === "")
            return "Off";

        return root.truncateApps(apps.trim());
    }
    function buildStatus(label, apps) {
        return apps !== "" ? label + ": " + apps : label + ": off";
    }
    function truncateApps(apps) {
        if (apps.length <= 32)
            return apps;

        return apps.slice(0, 29) + "...";
    }
    function updateFromPayload(payload) {
        if (!payload || typeof payload !== "object") {
            root.micActive = false;
            root.cameraActive = false;
            root.screenActive = false;
            root.locationActive = false;
            root.micApps = "";
            root.cameraApps = "";
            root.screenApps = "";
            root.locationApps = "";
            root.updateTooltip();
            return;
        }
        root.micActive = payload.mic === 1 || payload.mic === true;
        root.cameraActive = payload.cam === 1 || payload.cam === true;
        root.screenActive = payload.scr === 1 || payload.scr === true;
        root.locationActive = payload.loc === 1 || payload.loc === true;
        root.micApps = payload.mic_app ? String(payload.mic_app).trim() : "";
        root.cameraApps = payload.cam_app ? String(payload.cam_app).trim() : "";
        root.screenApps = payload.scr_app ? String(payload.scr_app).trim() : "";
        root.locationApps = payload.loc_app ? String(payload.loc_app).trim() : "";
        root.updateTooltip();
    }
    function updateTooltip() {
        const micStatus = root.buildStatus("Mic", root.micApps);
        const camStatus = root.buildStatus("Cam", root.cameraApps);
        const locStatus = root.buildStatus("Location", root.locationApps);
        const scrStatus = root.buildStatus("Screen sharing", root.screenApps);
        root.statusTooltip = micStatus + "  |  " + camStatus + "  |  " + locStatus + "  |  " + scrStatus;
    }

    collapsed: !root.micActive && !root.cameraActive && !root.screenActive && !root.locationActive
    contentSpacing: 8
    tooltipHoverable: true
    tooltipText: root.statusTooltip
    tooltipTitle: "Privacy"

    content: [
        Row {
            spacing: root.contentSpacing

            IconLabel {
                color: root.micColor
                text: root.micIcon
                visible: root.micActive
            }
            IconLabel {
                color: root.cameraColor
                text: root.cameraIcon
                visible: root.cameraActive
            }
            IconLabel {
                color: root.locationColor
                text: root.locationIcon
                visible: root.locationActive
            }
            IconLabel {
                color: root.screenColor
                text: root.screenIcon
                visible: root.screenActive
            }
        }
    ]
    tooltipContent: Component {
        ColumnLayout {
            spacing: Config.space.sm

            TooltipCard {
                content: [
                    InfoRow {
                        label: "Mic"
                        value: root.appLabel(root.micApps)
                        valueColor: root.micActive ? root.micColor : Config.m3.onSurfaceVariant
                    },
                    InfoRow {
                        label: "Camera"
                        value: root.appLabel(root.cameraApps)
                        valueColor: root.cameraActive ? root.cameraColor : Config.m3.onSurfaceVariant
                    },
                    InfoRow {
                        label: "Location"
                        value: root.appLabel(root.locationApps)
                        valueColor: root.locationActive ? root.locationColor : Config.m3.onSurfaceVariant
                    },
                    InfoRow {
                        label: "Screen"
                        value: root.appLabel(root.screenApps)
                        valueColor: root.screenActive ? root.screenColor : Config.m3.onSurfaceVariant
                    }
                ]
            }
            TooltipActionsRow {
                ActionChip {
                    text: "Refresh"

                    onClicked: privacyRunner.trigger()
                }
            }
        }
    }

    CommandRunner {
        id: privacyRunner

        command: root.scriptPath
        intervalMs: 3000

        onRan: function (output) {
            root.updateFromPayload(JsonUtils.parseObject(output));
        }
    }
}
