/**
 * @module PrivacyModule
 * @description Privacy indicator module showing active sensors (mic, camera, location, screen sharing)
 *
 * Features:
 * - Real-time monitoring of privacy-sensitive sensors
 * - Microphone usage detection via PipeWire (Quickshell service)
 * - Camera usage detection via PipeWire streams
 * - Screen sharing detection via PipeWire stream analysis
 * - Color-coded indicators (mic: green, camera: yellow, location: purple, screen: blue)
 *
 * Dependencies:
 * - PrivacyService (Quickshell.Services.Pipewire)
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
 * - Color customization via properties:
 *   - micColor: Config.color.tertiary (green)
 *   - cameraColor: Config.color.secondary (yellow)
 *   - locationColor: Config.color.tertiary (purple)
 *   - screenColor: Config.color.primary (blue)
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
 * PrivacyModule { }
 */
pragma ComponentBehavior: Bound
import ".."
import "../components"
import QtQuick
import QtQuick.Layouts

ModuleContainer {
    id: root

    property bool cameraActive: PrivacyService.cameraActive
    property string cameraApps: root.cameraActive ? "Active" : ""
    property color cameraColor: Config.color.secondary
    property string cameraIcon: ""
    property bool locationActive: false
    property string locationApps: ""
    property color locationColor: Config.color.tertiary
    property string locationIcon: ""
    property bool micActive: PrivacyService.microphoneActive
    property string micApps: root.micActive ? "Active" : ""
    property color micColor: Config.color.tertiary
    property string micIcon: ""
    property bool screenActive: PrivacyService.screensharingActive
    property string screenApps: root.screenActive ? "Active" : ""
    property color screenColor: Config.color.primary
    property string screenIcon: "󰍹"
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
    function updateTooltip() {
        const micStatus = root.buildStatus("Mic", root.micApps);
        const camStatus = root.buildStatus("Cam", root.cameraApps);
        const locStatus = root.buildStatus("Location", root.locationApps);
        const scrStatus = root.buildStatus("Screen sharing", root.screenApps);
        root.statusTooltip = micStatus + "  |  " + camStatus + "  |  " + locStatus + "  |  " + scrStatus;
    }

    Component.onCompleted: {
        root.updateTooltip();
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
                        valueColor: root.micActive ? root.micColor : Config.color.on_surface_variant
                    },
                    InfoRow {
                        label: "Camera"
                        value: root.appLabel(root.cameraApps)
                        valueColor: root.cameraActive ? root.cameraColor : Config.color.on_surface_variant
                    },
                    InfoRow {
                        label: "Location"
                        value: root.appLabel(root.locationApps)
                        valueColor: root.locationActive ? root.locationColor : Config.color.on_surface_variant
                    },
                    InfoRow {
                        label: "Screen"
                        value: root.appLabel(root.screenApps)
                        valueColor: root.screenActive ? root.screenColor : Config.color.on_surface_variant
                    }
                ]
            }
        }
    }

    onMicActiveChanged: root.updateTooltip()
    onCameraActiveChanged: root.updateTooltip()
    onLocationActiveChanged: root.updateTooltip()
    onScreenActiveChanged: root.updateTooltip()
    onMicAppsChanged: root.updateTooltip()
    onCameraAppsChanged: root.updateTooltip()
    onLocationAppsChanged: root.updateTooltip()
    onScreenAppsChanged: root.updateTooltip()
}
