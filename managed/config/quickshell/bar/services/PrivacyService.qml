pragma Singleton

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root

    property bool privacyStdoutLogging: true
    property bool privacyFileLogging: true
    property string cameraLogPath: "/tmp/quickshell-privacy-camera.log"
    property bool _cameraLogInitialized: false

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

    readonly property bool microphoneActive: {
        if (!Pipewire.ready || !Pipewire.nodes?.values) {
            return false
        }

        for (let i = 0; i < Pipewire.nodes.values.length; i++) {
            const node = Pipewire.nodes.values[i]
            if (!node) {
                continue
            }

            if ((node.type & PwNodeType.AudioInStream) === PwNodeType.AudioInStream) {
                if (!looksLikeSystemVirtualMic(node)) {
                    if (node.audio && node.audio.muted) {
                        continue
                    }
                    return true
                }
            }
        }
        return false
    }

    PwObjectTracker {
        objects: Pipewire.nodes.values.filter(node => !node.isStream)
    }

    readonly property bool cameraActive: {
        return root.v4l2OpenActive
    }

    readonly property bool screensharingActive: {
        if (!Pipewire.ready || !Pipewire.nodes?.values) {
            return false
        }

        for (let i = 0; i < Pipewire.nodes.values.length; i++) {
            const node = Pipewire.nodes.values[i]
            if (!node || !node.ready) {
                continue
            }

            if ((node.type & PwNodeType.VideoSource) === PwNodeType.VideoSource) {
                if (looksLikeScreencast(node)) {
                    return true
                }
            }

            if (node.properties && node.properties["media.class"] === "Stream/Input/Audio") {
                const mediaName = (node.properties["media.name"] || "").toLowerCase()
                const appName = (node.properties["application.name"] || "").toLowerCase()

                if (mediaName.includes("desktop") || appName.includes("screen") || appName === "obs") {
                    if (node.properties["stream.is-live"] === "true") {
                        if (node.audio && node.audio.muted) {
                            continue
                        }
                        return true
                    }
                }
            }
        }
        return false
    }

    readonly property bool anyPrivacyActive: microphoneActive || cameraActive || screensharingActive

    property bool v4l2OpenActive: false
    property string cameraDevice: "/dev/video0"
    property bool probingCamera: false
    property string fuserProbeStdout: ""
    property string fuserProbeStderr: ""
    property string cameraHoldersSummary: ""

    Process {
        id: inotifyProcess

        command: ["inotifywait", "-m", "-e", "open", "-e", "close", root.cameraDevice]
        running: true

        stdout: SplitParser {
            onRead: data => {
                if (!data) {
                    return
                }
                if (data.indexOf("OPEN") !== -1) {
                    root.v4l2OpenActive = true
                    root.probeCamera()
                    if (root.debugPrivacy) {
                        console.log("[PrivacyService] inotify OPEN", data.trim())
                    }
                } else if (data.indexOf("CLOSE") !== -1) {
                    root.probeCamera()
                    if (root.debugPrivacy) {
                        console.log("[PrivacyService] inotify CLOSE", data.trim())
                    }
                }
            }
        }

        stderr: SplitParser {
            onRead: data => {
                if (root.debugPrivacy && data && data.trim() !== "") {
                    console.log("[PrivacyService] inotify stderr", data.trim())
                }
            }
        }

        onExited: code => {
            if (code !== 0) {
                if (root.debugPrivacy) {
                    console.warn("[PrivacyService] inotifywait exited", code)
                }
                root.v4l2OpenActive = false
            }
        }
    }

    Process {
        id: fuserProbe

        command: ["fuser", "-v", root.cameraDevice]
        running: root.probingCamera

        stdout: SplitParser {
            onRead: data => {
                if (!data) {
                    return
                }
                root.fuserProbeStdout += data
            }
        }

        stderr: SplitParser {
            onRead: data => {
                if (!data) {
                    return
                }
                root.fuserProbeStderr += data
            }
        }

        onRunningChanged: {
            if (running) {
                root.fuserProbeStdout = ""
                root.fuserProbeStderr = ""
            }
        }

        onExited: code => {
            root.probingCamera = false
            root.logFuserCommandSnapshot()
            if (code === 0) {
                root.v4l2OpenActive = true
                if (root.debugPrivacy) {
                    console.log("[PrivacyService] fuser probe active")
                }
                return
            }
            if (code === 1) {
                root.v4l2OpenActive = false
                if (root.debugPrivacy) {
                    console.log("[PrivacyService] fuser probe inactive")
                }
                return
            }
            root.v4l2OpenActive = false
            if (root.debugPrivacy) {
                console.warn("[PrivacyService] fuser probe failed", code)
            }
        }
    }

    function probeCamera() {
        if (root.probingCamera) {
            return
        }
        root.probingCamera = true
    }

    Component.onCompleted: {
        root._cameraLogInitialized = true
        root.probeCamera()
    }

    onCameraActiveChanged: {
        if (!root._cameraLogInitialized) {
            root._cameraLogInitialized = true
            return
        }

        const details = root.describeCameraEvidence()
        const line = `[PrivacyService][${root.nowIso()}] camera ${root.cameraActive ? "ACTIVE" : "INACTIVE"}; ${details}`
        root.persistCameraLogLine(line)
        if (root.privacyStdoutLogging) {
            console.log(line)
        }
    }

    FileView {
        id: cameraLogFile
        path: root.cameraLogPath
        blockLoading: true
        printErrors: false
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.debugPrivacy
        triggeredOnStart: true
        onTriggered: {
            if (!Pipewire.ready || !Pipewire.nodes?.values) {
                console.log("[PrivacyService] Pipewire not ready")
                return
            }
            const videoIds = []
            try {
                console.log("[PrivacyService] Pipewire keys", JSON.stringify(Object.keys(Pipewire)))
                console.log("[PrivacyService] links available", Pipewire.links && Pipewire.links.values ? Pipewire.links.values.length : "none")
            } catch (err) {
                console.log("[PrivacyService] Pipewire keys stringify failed", err)
            }
            for (let i = 0; i < Pipewire.nodes.values.length; i++) {
                const node = Pipewire.nodes.values[i]
                if (!node || !node.ready || !node.properties) {
                    continue
                }
                const mediaClass = node.properties["media.class"] || ""
                if (mediaClass.indexOf("Video") === -1 && mediaClass.indexOf("Stream/Input/Video") === -1) {
                    continue
                }
                console.log(
                    "[PrivacyService] node",
                    mediaClass,
                    "name=" + (node.name || ""),
                    "app=" + (node.properties["application.name"] || ""),
                    "media.name=" + (node.properties["media.name"] || ""),
                    "live=" + (node.properties["stream.is-live"] || ""),
                    "state=" + root.stateString(node.state)
                )
                if (mediaClass.indexOf("Video") !== -1) {
                    if (node.id !== undefined && node.id !== null) {
                        videoIds.push(node.id)
                    }
                    try {
                        console.log("[PrivacyService] node props", JSON.stringify(node.properties))
                    } catch (err) {
                        console.log("[PrivacyService] node props stringify failed", err)
                    }
                    try {
                        console.log("[PrivacyService] node keys", JSON.stringify(Object.keys(node)))
                    } catch (err) {
                        console.log("[PrivacyService] node keys stringify failed", err)
                    }
                    console.log("[PrivacyService] node state raw", node.state, "active", node.active, "isStream", node.isStream)
                }
            }
            if (Pipewire.links?.values) {
                for (let i = 0; i < Pipewire.links.values.length; i++) {
                    const link = Pipewire.links.values[i]
                    if (!link) {
                        continue
                    }
                    const outId = link.outputNodeId || link.output_node_id || (link.output && link.output.node && link.output.node.id) || link.output_node || link.outputNode
                    const inId = link.inputNodeId || link.input_node_id || (link.input && link.input.node && link.input.node.id) || link.input_node || link.inputNode
                    const state = root.stateString(link.state)
                    const touchesVideo = videoIds.indexOf(outId) !== -1 || videoIds.indexOf(inId) !== -1
                    console.log("[PrivacyService] link state=" + state + " out=" + outId + " in=" + inId + (touchesVideo ? " video=true" : ""))
                    try {
                        console.log("[PrivacyService] link keys", JSON.stringify(Object.keys(link)))
                    } catch (err) {
                        console.log("[PrivacyService] link keys stringify failed", err)
                    }
                    try {
                        console.log("[PrivacyService] link raw", JSON.stringify(link))
                    } catch (err) {
                        console.log("[PrivacyService] link raw stringify failed", err)
                    }
                }
            }
        }
    }

    function looksLikeSystemVirtualMic(node) {
        if (!node) {
            return false
        }
        const name = (node.name || "").toLowerCase()
        const mediaName = (node.properties && node.properties["media.name"] || "").toLowerCase()
        const appName = (node.properties && node.properties["application.name"] || "").toLowerCase()
        const combined = name + " " + mediaName + " " + appName
        return /cava|monitor|system/.test(combined)
    }

    function looksLikeScreencast(node) {
        if (!node) {
            return false
        }
        const appName = (node.properties && node.properties["application.name"] || "").toLowerCase()
        const nodeName = (node.name || "").toLowerCase()
        const combined = appName + " " + nodeName
        return /xdg-desktop-portal|xdpw|screencast|screen|gnome shell|kwin|obs/.test(combined)
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

    function nowIso() {
        return (new Date()).toISOString()
    }

    function logFuserCommandSnapshot() {
        const raw = `${root.fuserProbeStdout || ""}\n${root.fuserProbeStderr || ""}`
        const lines = raw.split("\n")
        const hits = []
        for (let i = 0; i < lines.length; i++) {
            const line = (lines[i] || "").trim()
            if (!line || line.indexOf(root.cameraDevice) !== -1 || line.indexOf("USER") !== -1) {
                continue
            }
            const tokens = line.split(/\s+/)
            if (tokens.length < 5) {
                continue
            }
            const pid = tokens[1]
            const command = tokens[tokens.length - 1]
            if (/^\d+$/.test(pid)) {
                hits.push(`${pid}:${command}`)
            }
        }
        root.cameraHoldersSummary = hits.length > 0 ? hits.join(",") : ""
        if (hits.length > 0) {
            console.log(`[PrivacyService] ${root.cameraDevice} holders ${hits.join(", ")}`)
        } else if (root.debugPrivacy) {
            console.log(`[PrivacyService] ${root.cameraDevice} holders none`)
        }
    }

    function persistCameraLogLine(line) {
        if (!root.privacyFileLogging) {
            return
        }

        const prefix = cameraLogFile.text()
        const separator = prefix && prefix.length > 0 && !prefix.endsWith("\n") ? "\n" : ""
        cameraLogFile.setText((prefix || "") + separator + line)
    }

    function describeCameraEvidence() {
        const parts = []
        parts.push(`device=${root.cameraDevice}`)
        parts.push(`v4l2_open=${root.v4l2OpenActive ? "yes" : "no"}`)
        parts.push(`holders=${root.cameraHoldersSummary !== "" ? root.cameraHoldersSummary : "none"}`)

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

    function getMicrophoneStatus() {
        return microphoneActive ? "active" : "inactive"
    }

    function getCameraStatus() {
        return cameraActive ? "active" : "inactive"
    }

    function getScreensharingStatus() {
        return screensharingActive ? "active" : "inactive"
    }

    function getPrivacySummary() {
        const active = []
        if (microphoneActive) {
            active.push("microphone")
        }
        if (cameraActive) {
            active.push("camera")
        }
        if (screensharingActive) {
            active.push("screensharing")
        }

        return active.length > 0 ? `Privacy active: ${active.join(", ")}` : "No privacy concerns detected"
    }
}
