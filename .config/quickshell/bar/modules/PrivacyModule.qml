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

ModuleContainer {
  id: root

  readonly property bool cameraActive: PrivacyService.cameraActive
  property color cameraColor: Config.color.secondary
  property string cameraIcon: ""
  property bool locationActive: false
  property color locationColor: Config.color.tertiary
  property string locationIcon: ""
  readonly property bool micActive: PrivacyService.microphoneActive
  property color micColor: Config.color.tertiary
  property string micIcon: ""
  readonly property bool screenActive: PrivacyService.screensharingActive
  property color screenColor: Config.color.primary
  property string screenIcon: "󰍹"
  readonly property bool presentFrozen: PrivacyService.wlPresentFrozen
  property color presentFreezeColor: Config.color.primary
  property string presentFreezeIcon: ""

  collapsed: !root.micActive && !root.cameraActive && !root.screenActive && !root.locationActive && !root.presentFrozen
  contentSpacing: Config.space.sm

  onClicked: PrivacyService.togglePresentFreeze()

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
      IconLabel {
        color: root.presentFreezeColor
        text: root.presentFreezeIcon
        visible: root.presentFrozen
      }
    }
  ]
}
