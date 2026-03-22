import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property real freezeOpacity: 1
    property var captureProvider: null
    property url frozenFrame: ""
    property int frozenFrameAttempts: 0
    property bool initialFrozenGrabPending: true
    property var keyboardFocusMode: WlrKeyboardFocus.OnDemand
    default property alias overlayContent: overlayContainer.data
    property alias overlayRoot: overlayContainer
    property string pendingGrabScreenName: ""
    property string pendingGrabRequestId: ""
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
        if (!root.captureProvider)
            return;

        frozenFrameAttempts += 1;
        console.log("[freeze] capturing frame natively, attempt", frozenFrameAttempts);
        // Hide the overlay window, then wait a frame before starting native capture.
        root.surfaceTransparencyActive = true;
        root.pendingGrabScreenName = root.targetScreen.name;
        delayedCaptureStart.restart();
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
        pendingGrabRequestId = "";
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
        pendingGrabRequestId = "";
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
    Connections {
        target: root.captureProvider
        function onRequestFinished(requestId, filePath) {
            if (requestId !== root.pendingGrabRequestId)
                return;
            const path = `file://${filePath}`;
            console.log("[freeze] native capture success, setting frame:", path);
            root.pendingGrabRequestId = "";
            root.frozenFrame = "";
            root.frozenFrame = path;
            root.frozenFrameAttempts = 0;
            root.initialFrozenGrabPending = false;
            root.surfaceTransparencyActive = false;
        }
        function onRequestFailed(requestId, error) {
            if (requestId !== root.pendingGrabRequestId)
                return;
            console.log("[freeze] native capture failed:", error);
            root.pendingGrabRequestId = "";
            if (root.frozenFrameAttempts < 3) {
                retryFreezeGrab.start();
            } else {
                console.log("[freeze] giving up after native capture failures");
                root.surfaceTransparencyActive = false;
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
        id: delayedCaptureStart

        interval: 32
        repeat: false
        running: false

        onTriggered: {
            if (!root.screenFrozen)
                return;

            if (!root.targetScreen)
                return;

            if (root.pendingGrabScreenName === "")
                return;

            const path = `${root.runtimeDir}/hyprquickshot_frozen_${root.pendingGrabScreenName}.png`;
            root.pendingGrabRequestId = `freeze-${Date.now()}-${Math.round(Math.random() * 100000)}`;
            root.captureProvider.captureOutput(root.pendingGrabRequestId, root.pendingGrabScreenName, path, false);
        }
    }
}
