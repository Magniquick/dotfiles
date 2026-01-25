pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Qt.labs.settings
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Io

import "src" as Src
import "common" as Common

Src.FreezeScreen {
    id: root

    property bool active: false
    property var activeScreen: null
    property bool awaitingScreenConfirm: false
    property var countdownCenter: Qt.point(width / 2, height / 2)
    property int countdownValue: 3
    property bool grabReady: false
    property var hyprlandMonitor: Hyprland.focusedMonitor
    property string lastScreenshotPath: ""
    property bool lastScreenshotTemporary: false
    property string mode: "region"
    readonly property var colors: Common.Config.color
    readonly property string recordFlagPath: runtimeDir ? `${runtimeDir}/hyprquickshot-recording` : ""
    property bool recordMode: recordingState !== "idle"
    property var recordingSelection: null
    property string recordingState: "idle" // idle | selecting | countdown | recording
    property var regionSelectorItem: regionSelectorLoader.item
    readonly property bool runningStandalone: (Quickshell.shellDir || "").endsWith("/hyprquickshot")
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    property bool saveToDisk: true
    property bool sessionVisible: false
    property string tempPath
    property var windowSelectorItem: windowSelectorLoader.item

    function activate() {
        active = true;
        sessionVisible = false;
        grabReady = false;
        screenFrozen = true;
        resetSessionState();
        resetSelectionState();
        grabDelay.restart();
    }
    function beginCountdownForSelection(sel) {
        if (!sel || sel.width <= 0 || sel.height <= 0) {
            stopRecordFlow();
            return;
        }
        recordingSelection = sel;
        countdownCenter = Qt.point(sel.x + sel.width / 2, sel.y + sel.height / 2);
        recordingState = "countdown";
        countdownValue = 3;
        countdownPulse.restart();
        countdownTimer.start();
    }
    function cleanupTempPath() {
        if (!tempPath || tempPath === "")
            return;
        Quickshell.execDetached(["rm", "-f", tempPath]);
    }
    function clearRecordFlag() {
        if (!recordFlagPath)
            return;
        Quickshell.execDetached(["sh", "-c", `rm -f -- "${recordFlagPath}"`]);
    }
    function deactivate() {
        if (!active && !sessionVisible)
            return;
        console.log(`[state] deactivate active=${active} sessionVisible=${sessionVisible}`);
        active = false;
        sessionVisible = false;
        grabReady = false;
        grabDelay.stop();
        initialGrab.running = false;
        screenshotProcess.running = false;
        resetSessionState();
        if (runningStandalone)
            Qt.quit();
    }
    function notifyScreenshotSuccess() {
        if (!lastScreenshotPath || lastScreenshotPath === "")
            return;
        const summary = root.saveToDisk ? "Screenshot saved" : "Screenshot copied";
        const body = root.saveToDisk ? lastScreenshotPath : "Copied to clipboard";
        const scriptPath = (Quickshell.shellDir || "") + "/scripts/notify-screenshot.sh";
        if (Quickshell.shellDir && Quickshell.shellDir !== "") {
            Quickshell.execDetached([scriptPath, summary, body, lastScreenshotPath]);
        } else {
            Quickshell.execDetached(["notify-send", "-a", "HyprShot", summary, body]);
        }
    }
    function processScreenshot(x, y, width, height) {
        if (!root.active)
            return;
        if (width <= 0 || height <= 0)
            return;
        console.log(`[screenshot] processScreenshot start x=${x} y=${y} w=${width} h=${height}`);
        resetSelectionState();

        const rawScale = hyprlandMonitor && hyprlandMonitor.scale !== undefined ? Number(hyprlandMonitor.scale) : 1;
        const scale = rawScale && rawScale > 0 ? rawScale : 1;
        const scaledX = Math.round(x * scale);
        const scaledY = Math.round(y * scale);
        const scaledWidth = Math.round(width * scale);
        const scaledHeight = Math.round(height * scale);

        const homeDir = Quickshell.env("HOME") || "";
        const picturesBaseDir = Quickshell.env("HQS_DIR") || Quickshell.env("XDG_SCREENSHOTS_DIR") || (Quickshell.env("XDG_PICTURES_DIR") ? (Quickshell.env("XDG_PICTURES_DIR") + "/Screenshots") : "") || (homeDir ? (homeDir + "/Pictures/Screenshots") : "") || (homeDir + "/Pictures");
        const picturesDir = picturesBaseDir;
        const tempDir = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp";

        const now = new Date();
        const timestamp = Qt.formatDateTime(now, "yyyy-MM-dd_hh-mm-ss-zzz");

        const outputPath = root.saveToDisk ? `${picturesDir}/screenshot-${timestamp}.png` : `${tempDir}/hyprquickshot-preview-${timestamp}.png`;

        lastScreenshotTemporary = !root.saveToDisk;
        lastScreenshotPath = outputPath;

        let sourcePath = tempPath;

        if (root.screenFrozen && root.frozenFrame.toString() !== "") {
            sourcePath = root.frozenFrame.toString().replace("file://", "");
        }

        const screen = root.targetScreen;
        const geometry = `${screen.x},${screen.y} ${screen.width}x${screen.height}`;

        const captureCommand = (!root.screenFrozen) ? `grim -g "${geometry}" "${sourcePath}" && ` : "";

        const ensureDirCommand = root.saveToDisk ? `mkdir -p -- "${picturesDir}" && ` : "";

        screenshotProcess.command = ["sh", "-c", ensureDirCommand + captureCommand + `magick "${sourcePath}" -crop ${scaledWidth}x${scaledHeight}+${scaledX}+${scaledY} "${outputPath}" && ` + `rm -f -- "${tempPath}"`];

        screenshotProcess.running = false;
        screenshotProcess.running = true;
        root.sessionVisible = false;
    }
    function toggleSaveMode() {
        if (recordingState === "countdown" || recordingState === "recording")
            return;
        saveToDisk = !saveToDisk;
        if (settingsLoader.item)
            settingsLoader.item.saveToDisk = saveToDisk;
    }
    function resetSelectionState() {
        if (regionSelectorItem && typeof regionSelectorItem.resetSelection === "function")
            regionSelectorItem.resetSelection();
        if (windowSelectorItem && typeof windowSelectorItem.resetSelection === "function")
            windowSelectorItem.resetSelection();
    }
    function setMode(newMode) {
        if (mode === newMode)
            return;
        mode = newMode;
        if (recordingState === "selecting" || recordingState === "idle")
            awaitingScreenConfirm = newMode === "screen";
    }
    function toggleMode() {
        const cycle = ["window", "screen", "region"];
        const index = cycle.indexOf(mode);
        const nextMode = cycle[(index + 1) % cycle.length];
        setMode(nextMode);
    }
    function resetSessionState() {
        countdownTimer.stop();
        countdownValue = 3;
        recordingState = "idle";
        recordingSelection = null;
        awaitingScreenConfirm = false;
        mode = "region";
        activeScreen = null;
        sessionVisible = false;
        syncRecordFlag();
        cleanupTempPath();
        resetSelectionState();
        screenshotProcess.running = false;

        frozenFrame = "";
        frozenFrameAttempts = 0;
        initialFrozenGrabPending = true;
        surfaceTransparencyActive = false;
    }
    function selectFocusedMonitorAndGrab() {
        const monitor = Hyprland.focusedMonitor;
        if (!monitor)
            return;
        for (const screen of Quickshell.screens) {
            if (screen.name === monitor.name) {
                root.activeScreen = screen;

                const timestamp = Date.now();
                const path = Quickshell.cachePath(`screenshot-${timestamp}.png`);
                root.tempPath = path;
                initialGrab.command = ["grim", "-g", `${screen.x},${screen.y} ${screen.width}x${screen.height}`, path];
                initialGrab.running = true;
                return;
            }
        }
    }
    function startRecordFlow() {
        if (recordingState !== "idle")
            return;
        recordingSelection = null;
        if (mode === "screen") {
            awaitingScreenConfirm = true;
            recordingState = "selecting";
        } else {
            recordingState = "selecting";
        }
    }
    function stopRecordFlow() {
        countdownTimer.stop();
        countdownValue = 3;
        recordingState = "idle";
        recordingSelection = null;
        awaitingScreenConfirm = false;
    }
    function syncRecordFlag() {
        if (recordingState === "recording")
            writeRecordFlag();
        else
            clearRecordFlag();
    }
    function toggleActive() {
        if (active)
            deactivate();
        else
            activate();
    }
    function writeRecordFlag() {
        if (!recordFlagPath)
            return;
        Quickshell.execDetached(["sh", "-c", `touch -- "${recordFlagPath}"`]);
    }

    freezeOpacity: recordingState === "recording" ? 0.0 : 1.0
    keyboardFocusMode: recordingState === "recording" ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand
    mask: recordingState === "recording" ? emptyMask : fullMask
    screenFrozen: false
    targetScreen: activeScreen
    visible: active && sessionVisible

    Component.onCompleted: {
        if (!runningStandalone)
            return;
        if (!Qt.application.organization || Qt.application.organization === "")
            Qt.application.organization = "Hyprquickshot";
        if (!Qt.application.domain || Qt.application.domain === "")
            Qt.application.domain = "hyprquickshot";
        if (!Qt.application.name || Qt.application.name === "")
            Qt.application.name = "Hyprquickshot";

        settingsLoader.active = true;
        activate();
    }
    onRecordingStateChanged: syncRecordFlag()
    onSessionVisibleChanged: {
        if (sessionVisible)
            resetSelectionState();
    }

    Loader {
        id: settingsLoader

        active: false

        sourceComponent: Settings {
            id: settings

            property bool saveToDisk: true

            category: "Hyprquickshot"

            Component.onCompleted: root.saveToDisk = saveToDisk
            onSaveToDiskChanged: root.saveToDisk = saveToDisk
        }
    }
    Timer {
        id: grabDelay

        interval: 60
        repeat: false
        running: false

        onTriggered: {
            if (!root.active)
                return;
            root.grabReady = true;
            root.selectFocusedMonitorAndGrab();
            Qt.callLater(root.resetSelectionState);
        }
    }
    Connections {
        function onFocusedMonitorChanged() {
            root.selectFocusedMonitorAndGrab();
        }

        enabled: root.active && root.grabReady && root.activeScreen === null
        target: Hyprland
    }
    Shortcut {
        enabled: root.active
        sequence: "Escape"

        onActivated: () => {
            if (root.mode === "region" && root.regionSelectorItem && root.regionSelectorItem.selecting) {
                if (typeof root.regionSelectorItem.cancelSelection === "function")
                    root.regionSelectorItem.cancelSelection();
                else
                    root.resetSelectionState();
                return;
            }
            root.deactivate();
        }
    }
    Shortcut {
        enabled: root.active
        sequence: "Q"

        onActivated: () => {
            root.deactivate();
        }
    }
    Shortcut {
        enabled: root.active && root.recordingState !== "countdown" && root.recordingState !== "recording"
        sequence: "S"

        onActivated: () => {
            root.toggleSaveMode();
        }
    }
    Shortcut {
        enabled: root.active && root.recordingState !== "countdown" && root.recordingState !== "recording"
        sequence: "Tab"

        onActivated: () => {
            root.toggleMode();
        }
    }
    Timer {
        id: countdownTimer

        interval: 900
        repeat: true
        running: false

        onTriggered: {
            if (root.countdownValue > 1) {
                root.countdownValue -= 1;
                countdownPulse.restart();
            } else {
                countdownTimer.stop();
                root.recordingState = "recording";
            }
        }
    }
    Process {
        id: initialGrab

        property string stderrText: ""
        property string stdoutText: ""

        running: false

        stderr: StdioCollector {
            id: initialGrabStderr

            onStreamFinished: {
                initialGrab.stderrText = this.text;
            }
        }
        stdout: StdioCollector {
            id: initialGrabStdout

            onStreamFinished: {
                initialGrab.stdoutText = this.text;
            }
        }

        // qmllint disable signal-handler-parameters
        onExited: (exitCode, exitStatus) => {
            if (!root.active)
                return;
            console.log(`[state] initialGrab exited active=${root.active} sessionVisible=${root.sessionVisible}`);
            if (exitCode === 0) {
                root.sessionVisible = true;
                root.resetSelectionState();
                root.frozenFrame = "";
                root.frozenFrame = "file://" + root.tempPath;
                root.frozenFrameAttempts = 0;
                root.initialFrozenGrabPending = false;
                root.surfaceTransparencyActive = false;
            } else {
                const reason = initialGrab.stderrText || initialGrab.stdoutText || "Unknown error";
                Quickshell.execDetached(["notify-send", "-a", "HyprShot", "Failed to capture screen", `Code ${exitCode}: ${reason}`]);
                root.deactivate();
            }
        }
        // qmllint enable signal-handler-parameters
        onRunningChanged: {
            if (running) {
                initialGrab.stdoutText = "";
                initialGrab.stderrText = "";
            }
        }
    }
    Process {
        id: screenshotProcess

        property string stderrText: ""
        property string stdoutText: ""

        running: false

        stderr: StdioCollector {
            waitForEnd: true

            onStreamFinished: screenshotProcess.stderrText = this.text
        }
        stdout: StdioCollector {
            waitForEnd: true

            onStreamFinished: screenshotProcess.stdoutText = this.text
        }

        // qmllint disable signal-handler-parameters
        onExited: (exitCode, exitStatus) => {
            if (!root.active)
                return;
            console.log(`[state] screenshot exited active=${root.active} sessionVisible=${root.sessionVisible}`);
            console.log(`[screenshot] process exited code=${exitCode} status=${exitStatus}`);
            if (exitCode !== 0) {
                const reason = screenshotProcess.stderrText || screenshotProcess.stdoutText || `Command failed (code ${exitCode})`;
                Quickshell.execDetached(["notify-send", "-a", "HyprShot", "Screenshot failed", reason]);
                root.deactivate();
                if (root.runningStandalone)
                    Qt.quit();
                return;
            }

            if (root.lastScreenshotPath) {
                Quickshell.execDetached(["sh", "-c", `wl-copy < "${root.lastScreenshotPath}" >/dev/null 2>&1`]);
            }
            root.notifyScreenshotSuccess();
            root.resetSelectionState();
            console.log("[screenshot] deactivating after success");
            root.deactivate();
            if (root.runningStandalone)
                Qt.quit();
        }
        // qmllint enable signal-handler-parameters
        onRunningChanged: {
            if (running) {
                screenshotProcess.stdoutText = "";
                screenshotProcess.stderrText = "";
            }
        }
    }
    Loader {
        id: regionSelectorLoader

        active: root.sessionVisible && !root.initialFrozenGrabPending
        anchors.fill: parent

        sourceComponent: Src.RegionSelector {
            id: regionSelector

            anchors.fill: parent
            borderRadius: 10.0
            dimOpacity: 0.6
            outlineThickness: 2.0
            visible: (root.mode === "region" && root.recordingState !== "recording") || root.awaitingScreenConfirm

            onRegionSelected: (x, y, width, height) => {
                if (root.awaitingScreenConfirm) {
                    const insideControls = x >= controlWrapper.x && x <= (controlWrapper.x + controlWrapper.width) && y >= controlWrapper.y && y <= (controlWrapper.y + controlWrapper.height);
                    if (insideControls)
                        return;
                    root.awaitingScreenConfirm = false;
                    if (!root.targetScreen)
                        return;
                    if (root.recordingState === "selecting") {
                        root.beginCountdownForSelection({
                            x: 0,
                            y: 0,
                            width: root.targetScreen.width,
                            height: root.targetScreen.height
                        });
                    } else {
                        root.processScreenshot(0, 0, root.targetScreen.width, root.targetScreen.height);
                    }
                    return;
                }
                if (root.recordingState === "selecting") {
                    root.beginCountdownForSelection({
                        x,
                        y,
                        width,
                        height
                    });
                    return;
                }
                root.processScreenshot(x, y, width, height);
            }
        }
    }
    Loader {
        id: windowSelectorLoader

        active: root.sessionVisible && !root.initialFrozenGrabPending
        anchors.fill: parent

        sourceComponent: Src.WindowSelector {
            id: windowSelector

            anchors.fill: parent
            borderRadius: 10.0
            dimOpacity: 0.6
            monitor: root.hyprlandMonitor
            outlineThickness: 2.0
            visible: root.mode === "window" && root.recordingState !== "recording"

            onRegionSelected: (x, y, width, height) => {
                if (root.recordingState === "selecting") {
                    root.beginCountdownForSelection({
                        x,
                        y,
                        width,
                        height
                    });
                    return;
                }
                root.processScreenshot(x, y, width, height);
            }
        }
    }
    WrapperRectangle {
        id: controlWrapper

        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
        anchors.horizontalCenter: parent.horizontalCenter
        color: Qt.alpha(root.colors.surface, 0.93)
        margin: 8
        opacity: root.recordingState === "recording" ? 0 : 1
        radius: 12
        states: []
        visible: opacity > 0.05

        Behavior on opacity {
            NumberAnimation {
                duration: 180
                easing.type: Easing.InOutQuad
            }
        }
        transitions: Transition {
        }

        Row {
            id: settingRow

            spacing: 16

            Row {
                id: buttonRow

                enabled: root.recordingState !== "countdown" && root.recordingState !== "recording"
                opacity: 1
                spacing: 8

                Repeater {
                    model: [
                        {
                            mode: "region",
                            icon: "region"
                        },
                        {
                            mode: "window",
                            icon: "window"
                        },
                        {
                            mode: "screen",
                            icon: "screen"
                        }
                    ]

                    Button {
                        id: modeButton

                        required property var modelData

                        implicitHeight: 48
                        implicitWidth: 48

                        background: Rectangle {
                            color: {
                                if (root.mode === modeButton.modelData.mode)
                                    return Qt.alpha(root.colors.primary, 0.5);
                                if (modeButton.hovered)
                                    return Qt.alpha(root.colors.surface_container_high, 0.5);

                                return Qt.alpha(root.colors.surface_container, 0.5);
                            }
                            radius: 8

                            Behavior on color {
                                ColorAnimation {
                                    duration: 100
                                }
                            }
                        }
                        contentItem: Item {
                            anchors.fill: parent

                            Image {
                                anchors.centerIn: parent
                                fillMode: Image.PreserveAspectFit
                                height: 24
                                source: Qt.resolvedUrl(`icons/${modeButton.modelData.icon}.svg`)
                                width: 24
                            }
                        }

                        onClicked: {
                            root.setMode(modeButton.modelData.mode);
                        }
                    }
                }
            }
            Rectangle {
                id: divider

                anchors.verticalCenter: parent.verticalCenter
                color: Qt.alpha(root.colors.surface_container_high, 0.8)
                height: 32
                width: 1
            }
            Row {
                id: switchRow

                anchors.verticalCenter: buttonRow.verticalCenter
                spacing: 8

                Button {
                    id: freezeButton

                    Accessible.name: root.screenFrozen ? "Screen frozen" : "Screen live"
                    checkable: true
                    enabled: root.recordingState !== "countdown" && root.recordingState !== "recording"
                    implicitHeight: 48
                    implicitWidth: 48

                    background: Rectangle {
                        color: {
                            if (freezeButton.checked)
                                return Qt.alpha(root.colors.primary, 0.5);
                            if (freezeButton.hovered)
                                return Qt.alpha(root.colors.surface_container_high, 0.5);
                            return Qt.alpha(root.colors.surface_container, 0.5);
                        }
                        radius: 8

                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                            }
                        }
                    }
                    contentItem: Item {
                        anchors.fill: parent

                        Canvas {
                            id: freezeIcon

                            anchors.centerIn: parent
                            height: 24
                            width: 24

                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.resetTransform();
                                ctx.clearRect(0, 0, width, height);
                                ctx.fillStyle = root.colors.on_surface;

                                if (root.screenFrozen) {
                                    const barWidth = width / 4;
                                    const gap = barWidth / 1.2;
                                    const startX = (width - (2 * barWidth + gap)) / 2;
                                    const top = height * 0.2;
                                    const barHeight = height * 0.6;
                                    ctx.fillRect(startX, top, barWidth, barHeight);
                                    ctx.fillRect(startX + barWidth + gap, top, barWidth, barHeight);
                                } else {
                                    const padding = width * 0.28;
                                    ctx.beginPath();
                                    ctx.moveTo(padding, padding);
                                    ctx.lineTo(width - padding, height / 2);
                                    ctx.lineTo(padding, height - padding);
                                    ctx.closePath();
                                    ctx.fill();
                                }
                            }
                        }
                        Connections {
                            function onScreenFrozenChanged() {
                                if (freezeButton.checked !== root.screenFrozen) {
                                    freezeButton.checked = root.screenFrozen;
                                }
                                freezeIcon.requestPaint();
                            }

                            target: root
                        }
                    }

                    Component.onCompleted: freezeButton.checked = root.screenFrozen
                    onCheckedChanged: {
                        if (checked === root.screenFrozen)
                            return;
                        if (checked) {
                            root.freezeNow();
                        } else {
                            root.unfreezeNow();
                        }
                        freezeIcon.requestPaint();
                    }
                }
                Button {
                    id: saveButton

                    Accessible.name: "Save to disk"
                    checkable: true
                    checked: root.saveToDisk
                    enabled: root.recordingState !== "countdown" && root.recordingState !== "recording"
                    implicitHeight: 48
                    implicitWidth: 48

                    background: Rectangle {
                        color: {
                            if (saveButton.checked)
                                return Qt.alpha(root.colors.primary, 0.5);
                            if (saveButton.hovered)
                                return Qt.alpha(root.colors.surface_container_high, 0.5);
                            return Qt.alpha(root.colors.surface_container, 0.5);
                        }
                        radius: 8

                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                            }
                        }
                    }
                    contentItem: Item {
                        anchors.fill: parent

                        Image {
                            anchors.centerIn: parent
                            fillMode: Image.PreserveAspectFit
                            height: 24
                            source: Qt.resolvedUrl("icons/save.svg")
                            width: 24
                        }
                    }

                    onCheckedChanged: {
                        root.saveToDisk = checked;
                        if (settingsLoader.item)
                            settingsLoader.item.saveToDisk = checked;
                    }
                }
                Button {
                    id: recordButton

                    Accessible.name: "Recording indicator"
                    checkable: false
                    height: 48
                    scale: root.recordMode ? 1.05 : 1
                    transformOrigin: Item.Center
                    width: 48

                    background: Rectangle {
                        color: {
                            if (root.recordMode)
                                return Qt.alpha(root.colors.primary, 0.6);
                            if (recordButton.hovered)
                                return Qt.alpha(root.colors.surface_container_high, 0.5);
                            return Qt.alpha(root.colors.surface_container, 0.5);
                        }
                        radius: 8

                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                            }
                        }
                    }
                    contentItem: Item {
                        anchors.fill: parent

                        Image {
                            anchors.centerIn: parent
                            fillMode: Image.PreserveAspectFit
                            height: 24
                            source: (root.recordingState === "selecting" || root.recordingState === "countdown") ? Qt.resolvedUrl("icons/start.svg") : Qt.resolvedUrl("icons/record.svg")
                            width: 24
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.InOutQuad
                        }
                    }

                    onClicked: {
                        if (root.recordingState !== "idle")
                            return;
                        root.startRecordFlow();
                    }
                }
            }
        }
    }
    Item {
        id: countdownOverlay

        anchors.fill: parent
        opacity: visible ? 1 : 0
        visible: root.recordingState === "countdown"

        Behavior on opacity {
            NumberAnimation {
                duration: 180
                easing.type: Easing.InOutQuad
            }
        }

        Rectangle {
            id: countdownCircle

            border.color: Qt.alpha(root.colors.primary, 0.6)
            border.width: 2
            color: Qt.alpha(root.colors.surface, 0.8)
            height: 140
            radius: 70
            scale: 1.0
            width: 140
            x: root.countdownCenter.x - width / 2
            y: root.countdownCenter.y - height / 2
        }
        NumberAnimation {
            id: countdownPulse

            duration: 320
            easing.type: Easing.OutCubic
            from: 0.8
            property: "scale"
            target: countdownCircle
            to: 1.08
        }
        Text {
            anchors.centerIn: countdownCircle
            color: root.colors.on_surface
            font.bold: true
            font.pixelSize: 64
            text: root.countdownValue
        }
    }
    Item {
        id: fullMaskItem

        anchors.fill: parent
        visible: false
    }
    Region {
        id: fullMask

        item: fullMaskItem
    }
    Item {
        id: emptyMaskItem

        height: 0
        visible: false
        width: 0
    }
    Region {
        id: emptyMask

        item: emptyMaskItem
    }
}
