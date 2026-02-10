import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    property real freezeOpacity: 1
    property url frozenFrame: ""
    property int frozenFrameAttempts: 0
    property bool initialFrozenGrabPending: true
    property var keyboardFocusMode: WlrKeyboardFocus.OnDemand
    default property alias overlayContent: overlayContainer.data
    property alias overlayRoot: overlayContainer
    property string pendingGrabScreenName: ""
    property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    property bool screenFrozen: true
    property bool surfaceTransparencyActive: false
    property var targetScreen: Quickshell.screens[0]

    function clearCaptureTimers() {
        initialFreezeGrab.stop();
        retryFreezeGrab.stop();
    }
    function ensureFrozenFrame() {
        if (!root.screenFrozen) {
            console.log("[freeze] skip grab, not frozen");
            frozenFrameAttempts = 0;
            initialFrozenGrabPending = false;
            return;
        }
        if (!root.targetScreen) {
            console.log("[freeze] no target screen yet");
            frozenFrameAttempts = 0;
            return;
        }
        if (root.frozenFrame !== "" && !initialFrozenGrabPending) {
            console.log("[freeze] already have frame");
            root.surfaceTransparencyActive = false;
            return;
        }
        if (grimCapture.running)
            return;

        frozenFrameAttempts += 1;
        console.log("[freeze] capturing frame with grim, attempt", frozenFrameAttempts);
        // Hide window for capture, then wait a frame before starting grim.
        root.surfaceTransparencyActive = true;
        root.pendingGrabScreenName = root.targetScreen.name;
        delayedGrimStart.restart();
    }
    function freezeLater() {
        screenFrozen = true;
        root.ensureFrozenFrame();
        initialFreezeGrab.start();
    }
    function freezeNow() {
        if (screenFrozen)
            return;

        console.log("[freeze] freezing now");
        clearCaptureTimers();
        frozenFrame = "";
        frozenFrameAttempts = 0;
        initialFrozenGrabPending = true;
        freezeLater();
    }
    function unfreezeNow() {
        if (!screenFrozen)
            return;

        console.log("[freeze] unfreezing now");
        screenFrozen = false;
        frozenFrame = "";
        clearCaptureTimers();
        frozenFrameAttempts = 0;
        initialFrozenGrabPending = false;
        surfaceTransparencyActive = false;
    }

    WlrLayershell.keyboardFocus: keyboardFocusMode
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprquickshot"
    color: surfaceTransparencyActive ? "transparent" : (screenFrozen && frozenFrame === "" ? "black" : "transparent")
    exclusionMode: ExclusionMode.Ignore
    implicitHeight: targetScreen ? targetScreen.height : 0
    implicitWidth: targetScreen ? targetScreen.width : 0
    screen: targetScreen

    Component.onCompleted: {
        initialFrozenGrabPending = true;
        frozenFrame = "";
        if (screenFrozen) {
            surfaceTransparencyActive = true; // anticipate grab
            initialFreezeGrab.start();
        }
    }
    onScreenFrozenChanged: {
        console.log("[freeze] screenFrozen ->", screenFrozen);
        if (!screenFrozen) {
            unfreezeNow(); // Unify logic
            return;
        }
        root.ensureFrozenFrame();
    }
    onTargetScreenChanged: {
        console.log("[freeze] target screen changed; resetting attempts and clearing frame");
        frozenFrameAttempts = 0;
        frozenFrame = "";
        initialFrozenGrabPending = true;
        if (screenFrozen)
            root.ensureFrozenFrame();
    }
    onVisibleChanged: {
        if (visible && screenFrozen) {
            surfaceTransparencyActive = true;
            initialFreezeGrab.start();
        }
        if (!visible)
            surfaceTransparencyActive = false;
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        // While we make the surface fully transparent to grab a frame, keep an
        // invisible shield to avoid accidental clicks on whatever is behind.
        opacity: 0
        visible: root.surfaceTransparencyActive
        z: 9999

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            onPressed: function(mouse) {
                mouse.accepted = true;
            }
        }
    }
    Item {
        id: overlayContainer

        anchors.fill: parent
        opacity: root.surfaceTransparencyActive ? 0 : 1
        visible: !root.surfaceTransparencyActive

        Behavior on opacity {
            enabled: !root.surfaceTransparencyActive

            NumberAnimation {
                duration: 80
            }
        }
    }
    Process {
        id: grimCapture

        property string stderrText: ""
        property string stdoutText: ""

        running: false

        stderr: StdioCollector {
            onStreamFinished: grimCapture.stderrText = this.text
        }
        stdout: StdioCollector {
            onStreamFinished: grimCapture.stdoutText = this.text
        }

        // qmllint disable signal-handler-parameters
        onExited: exitCode => {
            console.log("[freeze] grim exited with code", exitCode);
            if (exitCode === 0) {
                const path = `file://${root.runtimeDir}/hyprquickshot_frozen_${root.targetScreen.name}.png`;
                console.log("[freeze] grim success, setting frame:", path);
                // Force reload if same path
                root.frozenFrame = "";
                root.frozenFrame = path;
                root.frozenFrameAttempts = 0;
                root.initialFrozenGrabPending = false;
                root.surfaceTransparencyActive = false;
            } else {
                console.log("[freeze] grim failed:", grimCapture.stderrText);
                if (root.frozenFrameAttempts < 3) {
                    retryFreezeGrab.start();
                } else {
                    console.log("[freeze] giving up after grim failures");
                    root.surfaceTransparencyActive = false;
                }
            }
        }
        // qmllint enable signal-handler-parameters
        onRunningChanged: {
            if (running) {
                grimCapture.stdoutText = "";
                grimCapture.stderrText = "";
            }
        }
    }
    Binding {
        property: "opacity"
        target: root.contentItem
        value: root.surfaceTransparencyActive ? 0 : 1
    }
    anchors {
        bottom: true
        left: true
        right: true
        top: true
    }
    Image {
        id: frozenImage

        anchors.fill: parent
        cache: false // Ensure we reload file changes
        fillMode: Image.Stretch
        opacity: root.freezeOpacity
        source: root.frozenFrame
        visible: root.screenFrozen && root.frozenFrame !== "" && !root.surfaceTransparencyActive
        z: -1

        onStatusChanged: {
            if (status === Image.Error) {
                console.log("[freeze] frozen image failed to load; clearing and retrying", source);
                root.frozenFrame = "";
                root.ensureFrozenFrame();
            }
        }
    }
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.freezeOpacity
        visible: root.screenFrozen && root.frozenFrame === "" && !root.surfaceTransparencyActive
        z: -1
    }
    Timer {
        id: initialFreezeGrab

        interval: 0
        repeat: false
        running: false

        onTriggered: {
            console.log("[timer] initialFreezeGrab triggered");
            root.ensureFrozenFrame();
        }
    }
    Timer {
        id: retryFreezeGrab

        interval: 0
        repeat: false
        running: false

        onTriggered: {
            console.log("[timer] retryFreezeGrab triggered");
            root.ensureFrozenFrame();
        }
    }
    Timer {
        id: delayedGrimStart

        interval: 32
        repeat: false
        running: false

        onTriggered: {
            if (!root.screenFrozen)
                return;

            if (!root.targetScreen)
                return;

            if (grimCapture.running)
                return;

            if (root.pendingGrabScreenName === "")
                return;

            const path = `${root.runtimeDir}/hyprquickshot_frozen_${root.pendingGrabScreenName}.png`;
            grimCapture.command = ["grim", "-o", root.pendingGrabScreenName, path];
            grimCapture.running = true;
        }
    }
}
