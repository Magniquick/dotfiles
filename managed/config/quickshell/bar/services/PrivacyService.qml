pragma Singleton

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root

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
                        return false
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
        if (!Pipewire.ready || !Pipewire.nodes?.values) {
            return false
        }

        if (root.inotifyAvailable) {
            return root.v4l2OpenActive
        }

        const liveVideoNode = root.findLiveVideoStream()
        if (liveVideoNode) {
            if (root.debugPrivacy) {
                console.log("[PrivacyService] camera active via live stream", liveVideoNode.name || "")
            }
            return true
        }

        const linkedVideoSource = root.findLinkedVideoSource()
        if (linkedVideoSource) {
            if (root.debugPrivacy) {
                console.log("[PrivacyService] camera active via linked source", linkedVideoSource.name || "")
            }
            return true
        }

        for (let i = 0; i < Pipewire.nodes.values.length; i++) {
            const node = Pipewire.nodes.values[i]
            if (!node || !node.ready) {
                continue
            }

            if (node.properties && node.properties["media.class"] === "Stream/Input/Video") {
                if (node.properties["stream.is-live"] === "true") {
                    if (root.debugPrivacy) {
                        console.log("[PrivacyService] camera active via stream", node.name || "", node.properties["application.name"] || "")
                    }
                    return true
                }
                if (root.stateString(node.state) === "running") {
                    if (root.debugPrivacy) {
                        console.log("[PrivacyService] camera active via running stream", node.name || "")
                    }
                    return true
                }
            }
        }
        if (root.debugPrivacy) {
            console.log("[PrivacyService] camera inactive (no live Stream/Input/Video)")
        }
        return false
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
                            return false
                        }
                        return true
                    }
                }
            }
        }
        return false
    }

    readonly property bool anyPrivacyActive: microphoneActive || cameraActive || screensharingActive

    property bool inotifyAvailable: true
    property bool fuserAvailable: true
    property bool v4l2OpenActive: false
    property string cameraDevice: "/dev/video0"
    property bool probingCamera: false

    Process {
        id: inotifyProcess

        command: ["inotifywait", "-m", "-e", "open", "-e", "close", root.cameraDevice]
        running: root.inotifyAvailable

        stdout: SplitParser {
            onRead: data => {
                if (!data) {
                    return
                }
                if (data.indexOf("OPEN") !== -1) {
                    root.v4l2OpenActive = true
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
                root.inotifyAvailable = false
                if (root.debugPrivacy) {
                    console.warn("[PrivacyService] inotifywait exited", code)
                }
                root.probeCamera()
            }
        }
    }

    Process {
        id: fuserProbe

        command: ["fuser", root.cameraDevice]
        running: root.probingCamera && root.fuserAvailable

        onExited: code => {
            root.probingCamera = false
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
            root.fuserAvailable = false
            if (root.debugPrivacy) {
                console.warn("[PrivacyService] fuser probe failed", code)
            }
        }
    }

    function probeCamera() {
        if (!root.fuserAvailable || root.probingCamera) {
            return
        }
        root.probingCamera = true
    }

    Component.onCompleted: {
        root.probeCamera()
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

    function findLiveVideoStream() {
        for (let i = 0; i < Pipewire.nodes.values.length; i++) {
            const node = Pipewire.nodes.values[i]
            if (!node || !node.ready || !node.properties) {
                continue
            }
            if (node.properties["media.class"] !== "Stream/Input/Video") {
                continue
            }
            if (node.properties["stream.is-live"] === "true") {
                return node
            }
            if ((node.state || "").toLowerCase() === "running") {
                return node
            }
        }
        return null
    }

    function findLinkedVideoSource() {
        if (!Pipewire.links?.values) {
            return null
        }
        for (let i = 0; i < Pipewire.nodes.values.length; i++) {
            const node = Pipewire.nodes.values[i]
            if (!node || !node.ready || !node.properties) {
                continue
            }
            if (node.properties["media.class"] !== "Video/Source") {
                continue
            }
            if (root.stateString(node.state) === "running") {
                return node
            }
            if (root.hasActiveLink(node)) {
                return node
            }
        }
        return null
    }

    function hasActiveLink(node) {
        if (!Pipewire.links?.values || node.id === undefined || node.id === null) {
            return false
        }
        for (let i = 0; i < Pipewire.links.values.length; i++) {
            const link = Pipewire.links.values[i]
            if (!link) {
                continue
            }
            const state = root.stateString(link.state)
            if (state !== "active") {
                continue
            }
            const outId = link.outputNodeId || link.output_node_id || (link.output && link.output.node && link.output.node.id) || link.output_node || link.outputNode
            const inId = link.inputNodeId || link.input_node_id || (link.input && link.input.node && link.input.node.id) || link.input_node || link.inputNode
            if (outId === node.id || inId === node.id) {
                return true
            }
        }
        return false
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
