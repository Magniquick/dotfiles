pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qsnative

Singleton {
  id: root

  property bool privacyStdoutLogging: true
  property bool privacyFileLogging: true
  property string cameraLogPath: "/tmp/quickshell-privacy-camera.log"
  property bool wlPresentFrozen: false

  readonly property bool debugPrivacy: {
    const value = Quickshell.env("QS_PRIVACY_DEBUG")
    if (value && value !== "0" && value !== "false") {
      return true
    }
    if (!Qt.application || !Qt.application.arguments) {
      return false
    }
    return Qt.application.arguments.indexOf("--qs-privacy-debug") !== -1
  }

  readonly property bool microphoneActive: privacyProvider.microphone_active
  readonly property bool cameraActive: privacyProvider.camera_active
  readonly property bool screensharingActive: privacyProvider.screensharing_active
  readonly property bool anyPrivacyActive: privacyProvider.any_privacy_active

  property alias cameraDevice: privacyProvider.camera_device
  readonly property bool cameraOpenSeen: privacyProvider.camera_open_seen
  readonly property bool cameraPendingConfirmation: privacyProvider.camera_pending_confirmation
  readonly property bool probingCamera: privacyProvider.probing_camera
  readonly property bool resolvingCameraApps: privacyProvider.probing_camera
  readonly property bool queuedCameraProbe: false
  readonly property string holderProbePidList: ""
  readonly property string holderProbeStdout: ""
  readonly property string holderProbeStderr: ""
  readonly property var cameraHolderApps: privacyProvider.camera_holder_apps.length > 0 ? privacyProvider.camera_holder_apps.split(", ") : []
  readonly property string cameraHoldersSummary: privacyProvider.camera_holders_summary
  readonly property int cameraRetryAttempt: privacyProvider.camera_retry_attempt
  readonly property int maxCameraRetryAttempts: 3
  readonly property int cameraRetryIntervalMs: 150
  readonly property string cameraActivationState: privacyProvider.camera_activation_state
  readonly property bool cameraDegraded: privacyProvider.camera_degraded
  readonly property string error: privacyProvider.error

  PwObjectTracker {
    objects: Pipewire.nodes.values.filter(node => !node.isStream)
  }

  PrivacyProvider {
    id: privacyProvider
    debug: root.debugPrivacy
    privacy_stdout_logging: root.privacyStdoutLogging
    privacy_file_logging: root.privacyFileLogging
    camera_log_path: root.cameraLogPath
  }

  Timer {
    interval: 500
    repeat: true
    running: Pipewire.ready
    triggeredOnStart: true
    onTriggered: root.updatePipewireSnapshot()
  }

  Component.onCompleted: {
    privacyProvider.start()
    root.updatePipewireSnapshot()
  }

  function updatePipewireSnapshot() {
    if (!Pipewire.ready || !Pipewire.nodes?.values) {
      privacyProvider.updatePipewireSnapshot("[]")
      if (root.debugPrivacy) {
        console.log("[PrivacyService] Pipewire not ready")
      }
      return
    }

    const nodes = []
    for (let i = 0; i < Pipewire.nodes.values.length; i++) {
      const node = Pipewire.nodes.values[i]
      if (!node || !node.ready) {
        continue
      }

      const props = node.properties || {}
      nodes.push({
        "name": node.name || "",
        "media_class": props["media.class"] || "",
        "media_name": props["media.name"] || "",
        "application_name": props["application.name"] || "",
        "stream_is_live": props["stream.is-live"] || "",
        "state": stateString(node.state),
        "audio_muted": !!(node.audio && node.audio.muted),
        "audio_in_stream": (node.type & PwNodeType.AudioInStream) === PwNodeType.AudioInStream,
        "video_source": (node.type & PwNodeType.VideoSource) === PwNodeType.VideoSource
      })
    }

    privacyProvider.updatePipewireSnapshot(JSON.stringify(nodes))
  }

  function queueCameraProbe() {
    privacyProvider.refreshCamera()
  }

  function startQueuedCameraProbe() {
  }

  function onCameraOpenEvent() {
    privacyProvider.refreshCamera()
  }

  function onCameraCloseEvent() {
    privacyProvider.refreshCamera()
  }

  function stateString(value) {
    if (value === undefined || value === null) {
      return ""
    }
    if (typeof value === "string") {
      return value.toLowerCase()
    }
    return String(value).toLowerCase()
  }

  function describeCameraEvidence() {
    const parts = []
    parts.push(`device=${root.cameraDevice}`)
    parts.push(`open_seen=${root.cameraOpenSeen ? "yes" : "no"}`)
    parts.push(`activation=${root.cameraActivationState}`)
    parts.push(`holder_count=${root.cameraHolderApps.length}`)
    parts.push(`holders=${root.cameraHoldersSummary !== "" ? root.cameraHoldersSummary : "none"}`)
    if (privacyProvider.camera_holder_apps !== "") {
      parts.push(`camera_apps=${privacyProvider.camera_holder_apps}`)
    }

    if (!Pipewire.ready || !Pipewire.nodes?.values) {
      parts.push("pipewire=not-ready")
      return parts.join(" ")
    }

    const apps = []
    const streams = []
    for (let i = 0; i < Pipewire.nodes.values.length; i++) {
      const node = Pipewire.nodes.values[i]
      if (!node || !node.ready || !node.properties) {
        continue
      }
      if (node.properties["media.class"] !== "Stream/Input/Video") {
        continue
      }

      const app = node.properties["application.name"] || ""
      if (app && apps.indexOf(app) === -1) {
        apps.push(app)
      }

      const state = root.stateString(node.state)
      const live = node.properties["stream.is-live"] || ""
      streams.push(`${node.name || "unnamed"}(state=${state},live=${live || "unknown"})`)
    }

    parts.push(`video_streams=${streams.length}`)
    if (apps.length > 0) {
      parts.push(`apps=${apps.join(",")}`)
    }
    if (streams.length > 0) {
      parts.push(`streams=${streams.join(";")}`)
    }
    return parts.join(" ")
  }

  function togglePresentFreeze() {
    root.wlPresentFrozen = !root.wlPresentFrozen
    Quickshell.execDetached(["wl-present", "toggle-freeze"])
  }
}
