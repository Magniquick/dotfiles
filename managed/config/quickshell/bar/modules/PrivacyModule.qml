/**
 * @module PrivacyModule
 * @description Privacy indicator module showing active sensors (mic, camera, location, screen sharing)
 *
 * Features:
 * - Real-time monitoring of privacy-sensitive sensors
 * - Microphone usage detection via PipeWire (pw-dump)
 * - Camera usage detection via /dev/video* file locks (fuser)
 * - Location service monitoring via geoclue process detection
 * - Screen sharing detection via PipeWire stream analysis
 * - Application name extraction for each active sensor
 * - Color-coded indicators (mic: green, camera: yellow, location: purple, screen: blue)
 * - Automatic script availability check
 *
 * Dependencies:
 * - privacy_dots.sh: Bash script that monitors all sensors
 *   - pw-dump (PipeWire): Audio and screen share detection
 *   - jq: JSON parsing
 *   - fuser: Camera device lock detection
 *   - geoclue: Location service process
 *   - ps: Process name extraction
 *
 * Script Output Format:
 * {
 *   "mic": 0|1,           // Microphone active
 *   "cam": 0|1,           // Camera active
 *   "loc": 0|1,           // Location active
 *   "scr": 0|1,           // Screen sharing active
 *   "mic_app": "app, ...", // Apps using microphone
 *   "cam_app": "app, ...", // Apps using camera
 *   "loc_app": "app, ...", // Apps using location
 *   "scr_app": "app, ..."  // Apps screen sharing
 * }
 *
 * Configuration:
 * - privacyRefreshMs: Polling interval (default: 1000ms / 1s)
 * - Color customization via properties:
 *   - micColor: Config.m3.success (green)
 *   - cameraColor: Config.m3.warning (yellow)
 *   - locationColor: Config.m3.tertiary (purple)
 *   - screenColor: Config.m3.primary (blue)
 *
 * Error Handling:
 * - Script availability check on startup
 * - JSON validation with fallback parsing (JsonUtils.safeParse)
 * - Graceful degradation when script unavailable or fails
 * - Error output handling from script
 * - Console warnings for missing dependencies
 *
 * Privacy Considerations:
 * - Monitors system-wide sensor usage (not per-application by default)
 * - Application names extracted when available via process inspection
 * - No data logged or transmitted - purely local monitoring
 *
 * @example
 * // Basic usage with defaults
 * PrivacyModule {}
 *
 * @example
 * // Custom refresh interval
 * PrivacyModule {
 *     privacyRefreshMs: 2000  // Check every 2 seconds
 * }
 */
pragma ComponentBehavior: Bound
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
    property bool scriptAvailable: false

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
        // Check for error in payload
        if (payload.error) {
            console.warn("PrivacyModule: Script error:", payload.error);
            root.statusTooltip = "Privacy: Error - " + payload.error;
            // Continue with default values from error payload
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

    Component.onCompleted: {
        DependencyCheck.requireExecutable(root.scriptPath, "PrivacyModule", function (available) {
            root.scriptAvailable = available;
            if (!available) {
                root.statusTooltip = "Privacy: Script not available";
            }
        });
    }
    CommandRunner {
        id: privacyRunner

        command: root.scriptPath
        enabled: root.scriptAvailable
        intervalMs: 3000
        logErrors: true

        onRan: function (output) {
            root.updateFromPayload(JsonUtils.parseObject(output));
        }

        onError: function (errorOutput, exitCode) {
            console.warn(`PrivacyModule: Script failed with exit code ${exitCode}`);
            if (errorOutput)
                console.warn(`PrivacyModule: stderr: ${errorOutput}`);
            root.statusTooltip = "Privacy: Script error (exit code " + exitCode + ")";
        }
    }
}
