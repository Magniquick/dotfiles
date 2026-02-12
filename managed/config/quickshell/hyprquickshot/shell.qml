pragma ComponentBehavior: Bound
import QtQuick
import Qt.labs.settings
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Io

import "src" as Src
import "src/ScreenshotUtils.js" as ScreenshotUtils
import "ui" as Ui
import "common" as Common
import "." as Hqs

Src.FreezeScreen {
    id: root

    property bool active: false
    property var activeScreen: null
    property bool awaitingScreenConfirm: false
    property var countdownCenter: Qt.point(width / 2, height / 2)
    property int countdownValue: Hqs.HqsConstants.countdownStartValue
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
    property bool _saveToDiskFallback: true
    readonly property bool saveToDisk: settingsLoader.item ? settingsLoader.item.saveToDisk : root._saveToDiskFallback
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
        countdownValue = Hqs.HqsConstants.countdownStartValue;
        countdownOverlay.pulse();
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
        Quickshell.execDetached(["rm", "-f", "--", recordFlagPath]);
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

        const screen = root.targetScreen;
        if (!screen)
            return;

        const env = {
            HOME: Quickshell.env("HOME") || "",
            HQS_DIR: Quickshell.env("HQS_DIR") || "",
            XDG_SCREENSHOTS_DIR: Quickshell.env("XDG_SCREENSHOTS_DIR") || "",
            XDG_PICTURES_DIR: Quickshell.env("XDG_PICTURES_DIR") || "",
            XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR") || ""
        };

        const plan = ScreenshotUtils.planScreenshot({
            x,
            y,
            width,
            height,
            monitorScale: hyprlandMonitor && hyprlandMonitor.scale !== undefined ? hyprlandMonitor.scale : 1,
            saveToDisk: root.saveToDisk,
            screenFrozen: root.screenFrozen,
            frozenFrame: root.frozenFrame,
            tempPath: root.tempPath,
            screenX: screen.x,
            screenY: screen.y,
            screenWidth: screen.width,
            screenHeight: screen.height,
            env: env,
            now: new Date()
        });

        root.lastScreenshotTemporary = plan.lastScreenshotTemporary;
        root.lastScreenshotPath = plan.outputPath;

	        screenshotProcess.command = Common.ProcessHelper.shell(plan.commandString);

        screenshotProcess.running = false;
        screenshotProcess.running = true;
        root.sessionVisible = false;
    }
    function toggleSaveMode() {
        if (recordingState === "countdown" || recordingState === "recording")
            return;
        root.setSaveToDisk(!root.saveToDisk);
    }

    function setSaveToDisk(value) {
        const next = !!value;
        if (settingsLoader.item) {
            settingsLoader.item.saveToDisk = next;
            return;
        }
        root._saveToDiskFallback = next;
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
        countdownValue = Hqs.HqsConstants.countdownStartValue;
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
        countdownValue = Hqs.HqsConstants.countdownStartValue;
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
        Quickshell.execDetached(["touch", "--", recordFlagPath]);
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
        }
    }
    Timer {
        id: grabDelay

        interval: Hqs.HqsConstants.grabDelayMs
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

        interval: Hqs.HqsConstants.countdownTickMs
        repeat: true
        running: false

        onTriggered: {
            if (root.countdownValue > 1) {
                root.countdownValue -= 1;
                countdownOverlay.pulse();
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
	                Common.ProcessHelper.execDetached(`wl-copy < "${root.lastScreenshotPath}" >/dev/null 2>&1`);
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
    Ui.ControlBar {
        id: controlWrapper

        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
        anchors.horizontalCenter: parent.horizontalCenter
        margin: 8
        colors: root.colors
        mode: root.mode
        recordingState: root.recordingState
        recordMode: root.recordMode
        saveToDisk: root.saveToDisk
        screenFrozen: root.screenFrozen

        onModeSelected: selectedMode => root.setMode(selectedMode)
        onRecordRequested: {
            if (root.recordingState !== "idle")
                return;
            root.startRecordFlow();
        }
        onSaveToDiskToggled: enabled => root.setSaveToDisk(enabled)
        onScreenFrozenToggled: frozen => {
            if (frozen === root.screenFrozen)
                return;
            if (frozen)
                root.freezeNow();
            else
                root.unfreezeNow();
        }
    }
    Ui.CountdownOverlay {
        id: countdownOverlay

        active: root.recordingState === "countdown"
        center: root.countdownCenter
        colors: root.colors
        value: root.countdownValue
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
