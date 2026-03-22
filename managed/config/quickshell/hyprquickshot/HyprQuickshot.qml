pragma ComponentBehavior: Bound
import QtQuick
import QtCore
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qscapture 1.0

import "src" as Src
import "src/ScreenshotUtils.js" as ScreenshotUtils
import "ui" as Ui
import "common" as Common
import "../common" as SharedCommon

Src.FreezeScreen {
    id: root

    readonly property int countdownStartValue: 3
    readonly property int countdownTickMs: 900
    readonly property int grabDelayMs: 60
    property bool active: false
    property var activeScreen: null
    property bool awaitingScreenConfirm: false
    property var countdownCenter: Qt.point(width / 2, height / 2)
    property int countdownValue: root.countdownStartValue
    property bool grabReady: false
    property var hyprlandMonitor: activeScreen ? Hyprland.monitorFor(activeScreen) : Hyprland.focusedMonitor
    property string lastScreenshotPath: ""
    property bool lastScreenshotTemporary: false
    property string mode: "region"
    readonly property var colors: Common.Config.color
    property string currentRecordingAudioDevice: ""
    property string currentRecordingPath: ""
    readonly property string recordFlagPath: runtimeDir ? `${runtimeDir}/hyprquickshot-recording` : ""
    property string _recordAudioModeFallback: "monitor"
    // qmllint disable missing-property
    readonly property string recordAudioMode: settingsLoader.item ? settingsLoader.item.recordAudioMode : root._recordAudioModeFallback
    // qmllint enable missing-property
    property bool recordMode: recordingState !== "idle" || recordProcess.running
    property var recordingSelection: null
    property string recordingState: "idle"
    property var regionSelectorItem: regionSelectorLoader.item
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    property bool _saveToDiskFallback: true
    // qmllint disable missing-property
    readonly property bool saveToDisk: settingsLoader.item ? settingsLoader.item.saveToDisk : root._saveToDiskFallback
    // qmllint enable missing-property
    property bool sessionVisible: false
    property bool screenshotFailureKeepsSession: false
    property string tempPath
    property bool wlScreenrecAvailable: false
    property bool pactlAvailable: false
    property string frozenWindowCacheState: "idle"
    property var frozenWindowTargets: []
    property string initialGrabRequestId: ""
    property string frozenWindowCacheRequestId: ""
    property string screenshotRequestId: ""
    property var windowSelectorItem: windowSelectorLoader.item
    readonly property var workspaceToplevels: hyprlandMonitor && hyprlandMonitor.activeWorkspace && hyprlandMonitor.activeWorkspace.toplevels ? hyprlandMonitor.activeWorkspace.toplevels.values : []
    readonly property var liveWindowTargets: root.buildWindowTargets(workspaceToplevels, hyprlandMonitor, false)
    readonly property var currentWindowTargets: root.screenFrozen ? root.frozenWindowTargets : root.liveWindowTargets
    readonly property bool windowModeLoading: root.screenFrozen && (root.initialFrozenGrabPending || root.frozenWindowCacheState === "capturing")
    readonly property bool windowModeAvailable: root.currentWindowTargets.length > 0

    function createRequestId(prefix) {
        return `${prefix}-${Date.now()}-${Math.round(Math.random() * 100000)}`;
    }
    function resolveScreenshotOutput() {
        return ScreenshotUtils.resolveScreenshotOutput({
            env: root.environment(),
            now: new Date(),
            saveToDisk: root.saveToDisk
        });
    }
    function beginScreenshotCapture(requestId, output) {
        root.screenshotRequestId = requestId;
        root.lastScreenshotTemporary = !!output.temporary;
        root.lastScreenshotPath = String(output.outputPath || "");
        root.sessionVisible = false;
    }

    function asList(value) {
        if (!value)
            return [];
        if (Array.isArray(value))
            return value;
        if (value.length !== undefined) {
            const list = [];
            for (let index = 0; index < Number(value.length); index += 1)
                list.push(value[index]);
            return list;
        }
        return [];
    }
    function buildWindowTarget(toplevel, monitor, frozen) {
        const monitorObject = monitor && monitor.lastIpcObject ? monitor.lastIpcObject : null;
        const ipcObject = toplevel && toplevel.lastIpcObject ? toplevel.lastIpcObject : null;
        const stableId = ipcObject && ipcObject.stableId ? String(ipcObject.stableId) : "";
        if (!monitorObject || !ipcObject || !ipcObject.at || !ipcObject.size || stableId === "")
            return null;

        const token = `${Date.now()}-${Math.round(Math.random() * 100000)}`;
        return {
            stableId: stableId,
            x: Number(ipcObject.at[0]) - Number(monitorObject.x),
            y: Number(ipcObject.at[1]) - Number(monitorObject.y),
            width: Number(ipcObject.size[0]),
            height: Number(ipcObject.size[1]),
            title: String(ipcObject.title || ""),
            className: String(ipcObject.class || ""),
            captureState: frozen ? "pending" : "ready",
            imagePath: frozen ? Quickshell.cachePath(`hyprquickshot-window-${token}-${stableId}.png`) : ""
        };
    }
    function buildWindowTargets(toplevels, monitor, frozen) {
        const targets = [];
        const source = root.asList(toplevels);
        const workspace = monitor && monitor.activeWorkspace ? monitor.activeWorkspace : null;

        console.log("[window-targets] build start",
            "frozen=", frozen,
            "monitor=", monitor ? monitor.name : "null",
            "workspace=", workspace ? workspace.name : "null",
            "sourceCount=", source.length);

        for (const toplevel of source) {
            const target = root.buildWindowTarget(toplevel, monitor, frozen);
            if (target)
                targets.push(target);
        }

        console.log("[window-targets] build complete",
            "frozen=", frozen,
            "targetCount=", targets.length,
            "stableIds=", JSON.stringify(targets.map(target => target.stableId)));
        return targets;
    }
    function cleanupFrozenWindowCache() {
        console.log("[window-targets] cleanup frozen cache",
            "requestId=", root.frozenWindowCacheRequestId,
            "targetCount=", root.frozenWindowTargets.length);
        root.frozenWindowCacheRequestId = "";

        const targets = Array.isArray(root.frozenWindowTargets) ? root.frozenWindowTargets : [];
        const paths = [];

        for (const target of targets) {
            const imagePath = target && target.imagePath ? String(target.imagePath) : "";
            if (imagePath !== "")
                paths.push(imagePath);
        }

        if (paths.length > 0) {
            const command = ["rm", "-f", "--"];
            for (const path of paths)
                command.push(path);
            Quickshell.execDetached(command);
        }

        root.frozenWindowTargets = [];
        root.frozenWindowCacheState = "idle";
    }
    function startFrozenWindowCacheCapture() {
        if (!root.active || !root.screenFrozen || root.frozenFrame === "")
            return;

        root.cleanupFrozenWindowCache();
        root.frozenWindowTargets = root.buildWindowTargets(root.workspaceToplevels, root.hyprlandMonitor, true);
        root.frozenWindowCacheState = root.frozenWindowTargets.length > 0 ? "capturing" : "ready";
        console.log("[window-targets] frozen cache start",
            "state=", root.frozenWindowCacheState,
            "count=", root.frozenWindowTargets.length);
        if (root.frozenWindowTargets.length === 0) {
            Qt.callLater(root.syncSelectorPreview);
            return;
        }

        const requests = [];
        for (const target of root.frozenWindowTargets)
            requests.push({ identifier: target.stableId, filePath: target.imagePath });
        root.frozenWindowCacheRequestId = root.createRequestId("frozen-window-cache");
        console.log("[window-targets] launching frozen cache capture", "requestId=", root.frozenWindowCacheRequestId);
        captureProvider.captureToplevelBatch(root.frozenWindowCacheRequestId, requests, false);
    }
    function syncSelectorPreview() {
        if (!sessionVisible || initialFrozenGrabPending)
            return;
        if (mode === "window" && !windowModeAvailable) {
            resetSelectionState();
            return;
        }
        if (awaitingScreenConfirm) {
            if (regionSelectorItem && typeof regionSelectorItem.setSelectionRect === "function")
                regionSelectorItem.setSelectionRect(0, 0, regionSelectorItem.width, regionSelectorItem.height);
            return;
        }
        if (mode === "window" && windowSelectorItem && typeof windowSelectorItem.refreshHover === "function") {
            windowSelectorItem.refreshHover();
            return;
        }
        resetSelectionState();
    }
    function syncGlobalState() {
        SharedCommon.GlobalState.screenRecordingActive = recordProcess.running;
        SharedCommon.GlobalState.screenRecordingAudioDevice = currentRecordingAudioDevice;
        SharedCommon.GlobalState.screenRecordingAudioMode = recordAudioMode;
        SharedCommon.GlobalState.screenRecordingPath = currentRecordingPath;
        SharedCommon.GlobalState.screenRecordingPid = recordProcess.processId === null || recordProcess.processId === undefined ? 0 : Number(recordProcess.processId);
        SharedCommon.GlobalState.screenRecordingState = recordingState;
        SharedCommon.GlobalState.hyprQuickshotVisible = active;
    }
    function activate() {
        if (recordProcess.running) {
            stopActiveRecording();
            return;
        }
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
        countdownValue = root.countdownStartValue;
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
    function clearRecordingMetadata() {
        currentRecordingAudioDevice = "";
        currentRecordingPath = "";
    }
    function environment() {
        return {
            HOME: Quickshell.env("HOME") || "",
            HQS_DIR: Quickshell.env("HQS_DIR") || "",
            XDG_SCREENSHOTS_DIR: Quickshell.env("XDG_SCREENSHOTS_DIR") || "",
            XDG_PICTURES_DIR: Quickshell.env("XDG_PICTURES_DIR") || "",
            XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR") || ""
        };
    }
    function deactivate() {
        if (!active && !sessionVisible)
            return;
        if (recordProcess.running) {
            stopActiveRecording();
            return;
        }
        active = false;
        sessionVisible = false;
        grabReady = false;
        screenshotFailureKeepsSession = false;
        grabDelay.stop();
        resetSessionState();
    }
    function notifyRecordingFailure(reason) {
        Quickshell.execDetached(["notify-send", "-a", "HyprShot", "Recording failed", reason]);
    }
    function notifyRecordingSuccess() {
        if (!currentRecordingPath || currentRecordingPath === "")
            return;
        Quickshell.execDetached(["notify-send", "-a", "HyprShot", "Recording saved", currentRecordingPath]);
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
        if (!root.active || width <= 0 || height <= 0)
            return;
        resetSelectionState();

        const screen = root.targetScreen;
        if (!screen)
            return;

        const output = root.resolveScreenshotOutput();
        const requestId = root.createRequestId("screenshot");
        root.screenshotFailureKeepsSession = false;
        root.beginScreenshotCapture(requestId, output);

        if (root.screenFrozen) {
            const sourcePath = ScreenshotUtils.stripFileUrl(root.frozenFrame);
            const fullScreenSelection = x === 0 && y === 0 && width === screen.width && height === screen.height;
            if (fullScreenSelection)
                captureProvider.copyImageFile(requestId, sourcePath, output.outputPath);
            else
                captureProvider.cropImageFile(requestId, sourcePath, x, y, width, height, hyprlandMonitor && hyprlandMonitor.scale !== undefined ? hyprlandMonitor.scale : 1, output.outputPath);
            return;
        }

        const fullScreenSelection = x === 0 && y === 0 && width === screen.width && height === screen.height;
        if (fullScreenSelection)
            captureProvider.captureOutput(requestId, screen.name || (hyprlandMonitor ? hyprlandMonitor.name : ""), output.outputPath, false);
        else
            captureProvider.captureRegion(requestId, screen.x + x, screen.y + y, width, height, output.outputPath, hyprlandMonitor && hyprlandMonitor.scale !== undefined ? hyprlandMonitor.scale : 1, false);
    }
    function processWindowScreenshot(target) {
        if (!root.active || !target || !target.stableId)
            return;

        resetSelectionState();

        const output = root.resolveScreenshotOutput();
        const requestId = root.createRequestId("window-screenshot");
        if (root.screenFrozen) {
            if (root.windowModeLoading || target.captureState !== "ready" || !target.imagePath)
                return;
            root.screenshotFailureKeepsSession = true;
            root.beginScreenshotCapture(requestId, output);
            captureProvider.copyImageFile(requestId, target.imagePath, output.outputPath);
        } else {
            root.screenshotFailureKeepsSession = true;
            root.beginScreenshotCapture(requestId, output);
            captureProvider.captureToplevel(requestId, target.stableId, output.outputPath, false);
        }
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
    function setRecordAudioMode(modeValue) {
        const next = modeValue === "defaultMic" || modeValue === "off" ? modeValue : "monitor";
        if (settingsLoader.item) {
            settingsLoader.item.recordAudioMode = next;
            return;
        }
        root._recordAudioModeFallback = next;
    }
    function setMode(newMode) {
        if (mode === newMode)
            return;
        mode = newMode;
        if (newMode === "window") {
            Hyprland.refreshMonitors();
            Hyprland.refreshWorkspaces();
            Hyprland.refreshToplevels();
        }
        if (recordingState === "selecting" || recordingState === "idle")
            awaitingScreenConfirm = newMode === "screen";
        Qt.callLater(root.syncSelectorPreview);
    }
    function toggleMode() {
        const cycle = ["window", "screen", "region"];
        const index = cycle.indexOf(mode);
        for (let offset = 1; offset <= cycle.length; offset += 1) {
            const nextMode = cycle[(index + offset) % cycle.length];
            setMode(nextMode);
            return;
        }
    }
    function resetSessionState() {
        countdownTimer.stop();
        countdownValue = root.countdownStartValue;
        recordingState = "idle";
        recordingSelection = null;
        awaitingScreenConfirm = false;
        mode = "region";
        activeScreen = null;
        sessionVisible = false;
        screenshotFailureKeepsSession = false;
        initialGrabRequestId = "";
        screenshotRequestId = "";
        frozenWindowCacheRequestId = "";
        syncRecordFlag();
        cleanupTempPath();
        cleanupFrozenWindowCache();
        clearRecordingMetadata();
        resetSelectionState();
        frozenFrame = "";
        frozenFrameAttempts = 0;
        initialFrozenGrabPending = true;
        surfaceTransparencyActive = false;
    }
    function selectFocusedMonitorAndGrab() {
        const preferredScreen = SharedCommon.GlobalState.hyprQuickshotScreen;
        const monitor = Hyprland.focusedMonitor;
        let selectedScreen = null;
        if (preferredScreen)
            selectedScreen = preferredScreen;
        if (!selectedScreen && monitor) {
            for (const screen of Quickshell.screens) {
                if (screen.name === monitor.name) {
                    selectedScreen = screen;
                    break;
                }
            }
        }
        if (!selectedScreen && Quickshell.screens.length > 0)
            selectedScreen = Quickshell.screens[0];
        if (!selectedScreen)
            return;
        SharedCommon.GlobalState.hyprQuickshotScreen = selectedScreen;
        root.activeScreen = selectedScreen;
        const timestamp = Date.now();
        const path = Quickshell.cachePath(`screenshot-${timestamp}.png`);
        root.tempPath = path;
        root.initialGrabRequestId = root.createRequestId("initial-freeze");
        captureProvider.captureOutput(root.initialGrabRequestId, selectedScreen.name, path, false);
    }
    function startRecordFlow() {
        if (recordingState !== "idle")
            return;
        if (!wlScreenrecAvailable) {
            notifyRecordingFailure("wl-screenrec is not available");
            return;
        }
        if ((recordAudioMode === "monitor" || recordAudioMode === "defaultMic") && !pactlAvailable) {
            notifyRecordingFailure("pactl is required to resolve the selected audio source");
            return;
        }
        recordingSelection = null;
        recordingState = "selecting";
        awaitingScreenConfirm = mode === "screen";
    }
    function startRecording(selection) {
        if (!selection || selection.width <= 0 || selection.height <= 0) {
            stopRecordFlow();
            return;
        }
        const plan = ScreenshotUtils.planRecording({
            audioMode: root.recordAudioMode,
            env: {
                HOME: Quickshell.env("HOME") || "",
                XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR") || "",
                XDG_VIDEOS_DIR: Quickshell.env("XDG_VIDEOS_DIR") || ""
            },
            mode: root.mode,
            now: new Date(),
            targetScreen: root.targetScreen,
            x: selection.x,
            y: selection.y,
            width: selection.width,
            height: selection.height
        });
        currentRecordingPath = plan.outputPath;
        currentRecordingAudioDevice = root.recordAudioMode === "monitor" ? "default monitor" : (root.recordAudioMode === "defaultMic" ? "default mic" : "");
        recordProcess.command = Common.ProcessHelper.shell(plan.commandString);
        recordProcess.running = false;
        recordProcess.running = true;
        recordingState = "recording";
        sessionVisible = false;
        awaitingScreenConfirm = false;
        recordingSelection = selection;
    }
    function stopRecordFlow() {
        countdownTimer.stop();
        countdownValue = root.countdownStartValue;
        recordingState = "idle";
        recordingSelection = null;
        awaitingScreenConfirm = false;
    }
    function stopActiveRecording() {
        countdownTimer.stop();
        if (recordProcess.running) {
            recordProcess.signal(2);
            return;
        }
        stopRecordFlow();
    }
    function syncRecordFlag() {
        if (recordProcess.running || recordingState === "recording")
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
    captureProvider: captureProvider
    keyboardFocusMode: recordingState === "recording" ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand
    mask: recordingState === "recording" ? emptyMask : fullMask
    screenFrozen: false
    targetScreen: activeScreen
    visible: active && sessionVisible

    Component.onCompleted: {
        SharedCommon.GlobalState.registerHyprQuickshot(root);
        if (!Qt.application.organization || Qt.application.organization === "")
            Qt.application.organization = "Hyprquickshot";
        if (!Qt.application.domain || Qt.application.domain === "")
            Qt.application.domain = "hyprquickshot";
        if (!Qt.application.name || Qt.application.name === "")
            Qt.application.name = "Hyprquickshot";
        settingsLoader.active = true;
        Common.DependencyCheck.require("wl-screenrec", "HyprQuickshot", function(available) {
            root.wlScreenrecAvailable = available;
        });
        Common.DependencyCheck.require("pactl", "HyprQuickshot", function(available) {
            root.pactlAvailable = available;
        });
        if (SharedCommon.GlobalState.hyprQuickshotVisible)
            activate();
        root.syncGlobalState();
    }
    Connections {
        target: SharedCommon.GlobalState
        function onHyprQuickshotVisibleChanged() {
            if (SharedCommon.GlobalState.hyprQuickshotVisible) {
                if (!root.active)
                    root.activate();
            } else if (root.active && !recordProcess.running) {
                root.deactivate();
            }
        }
    }
    Component.onDestruction: {
        if (SharedCommon.GlobalState.hyprQuickshotController === root)
            SharedCommon.GlobalState.registerHyprQuickshot(null);
        SharedCommon.GlobalState.hyprQuickshotVisible = false;
        SharedCommon.GlobalState.resetScreenRecordingState();
    }
    onActiveChanged: root.syncGlobalState()
    onCurrentRecordingAudioDeviceChanged: root.syncGlobalState()
    onCurrentRecordingPathChanged: root.syncGlobalState()
    onRecordAudioModeChanged: root.syncGlobalState()
    onRecordingStateChanged: {
        syncRecordFlag();
        root.syncGlobalState();
    }
    onFrozenFrameChanged: {
        if (root.screenFrozen && root.frozenFrame !== "")
            root.startFrozenWindowCacheCapture();
        else if (!root.screenFrozen)
            root.cleanupFrozenWindowCache();
    }
    onFrozenWindowCacheStateChanged: Qt.callLater(root.syncSelectorPreview)
    onCurrentWindowTargetsChanged: {
        console.log("[window-targets] current targets changed",
            "mode=", root.mode,
            "screenFrozen=", root.screenFrozen,
            "loading=", root.windowModeLoading,
            "count=", root.currentWindowTargets.length);
        if (!root.windowModeLoading && !root.windowModeAvailable)
            root.resetSelectionState();
    }
    onSessionVisibleChanged: {
        if (sessionVisible)
            Qt.callLater(root.syncSelectorPreview);
    }

    Loader {
        id: settingsLoader
        active: false
        sourceComponent: Settings {
            property bool saveToDisk: true
            property string recordAudioMode: "monitor"
            category: "Hyprquickshot"
        }
    }
    CaptureProvider {
        id: captureProvider
    }
    Connections {
        target: captureProvider
        function onRequestFinished(requestId, filePath) {
            if (requestId === root.initialGrabRequestId) {
                if (!root.active)
                    return;
                root.initialGrabRequestId = "";
                root.sessionVisible = true;
                root.resetSelectionState();
                root.frozenFrame = "";
                root.frozenFrame = "file://" + filePath;
                root.frozenFrameAttempts = 0;
                root.initialFrozenGrabPending = false;
                root.surfaceTransparencyActive = false;
                Qt.callLater(root.syncSelectorPreview);
                return;
            }

            if (requestId === root.screenshotRequestId) {
                if (!root.active)
                    return;
                root.screenshotRequestId = "";
                if (root.lastScreenshotPath)
                    Common.ProcessHelper.execDetached(`wl-copy < "${root.lastScreenshotPath}" >/dev/null 2>&1`);
                root.notifyScreenshotSuccess();
                root.resetSelectionState();
                root.screenshotFailureKeepsSession = false;
                root.deactivate();
            }
        }
        function onRequestFailed(requestId, error) {
            if (requestId === root.initialGrabRequestId) {
                if (!root.active)
                    return;
                root.initialGrabRequestId = "";
                Quickshell.execDetached(["notify-send", "-a", "HyprShot", "Failed to capture screen", error]);
                root.deactivate();
                return;
            }

            if (requestId === root.frozenWindowCacheRequestId) {
                if (!root.active || !root.screenFrozen)
                    return;
                console.log("[window-targets] frozen cache failed", "requestId=", requestId, "reason=", error);
                root.frozenWindowCacheRequestId = "";
                root.cleanupFrozenWindowCache();
                Quickshell.execDetached(["notify-send", "-a", "HyprShot", "Frozen window capture failed", error]);
                root.deactivate();
                return;
            }

            if (requestId === root.screenshotRequestId) {
                if (!root.active)
                    return;
                root.screenshotRequestId = "";
                Quickshell.execDetached(["notify-send", "-a", "HyprShot", "Screenshot failed", error]);
                if (root.screenshotFailureKeepsSession) {
                    root.screenshotFailureKeepsSession = false;
                    root.sessionVisible = true;
                    Qt.callLater(root.syncSelectorPreview);
                } else {
                    root.deactivate();
                }
            }
        }
        function onBatchFinished(requestId) {
            if (requestId !== root.frozenWindowCacheRequestId)
                return;
            const readyTargets = [];
            for (const target of root.frozenWindowTargets) {
                readyTargets.push({
                    stableId: target.stableId,
                    x: target.x,
                    y: target.y,
                    width: target.width,
                    height: target.height,
                    title: target.title,
                    className: target.className,
                    captureState: "ready",
                    imagePath: target.imagePath
                });
            }
            root.frozenWindowCacheRequestId = "";
            root.frozenWindowTargets = readyTargets;
            root.frozenWindowCacheState = "ready";
            Qt.callLater(root.syncSelectorPreview);
        }
        function onBatchFailed(requestId, error, completedCount) {
            if (requestId !== root.frozenWindowCacheRequestId)
                return;
            if (!root.active || !root.screenFrozen)
                return;
            console.log("[window-targets] frozen cache failed",
                "requestId=", requestId,
                "completedCount=", completedCount,
                "reason=", error);
            root.frozenWindowCacheRequestId = "";
            root.cleanupFrozenWindowCache();
            Quickshell.execDetached(["notify-send", "-a", "HyprShot", "Frozen window capture failed", error]);
            root.deactivate();
        }
    }
    IpcHandler {
        target: "hyprquickshot-recording"
        function status(): string {
            return JSON.stringify({
                active: recordProcess.running,
                audioDevice: root.currentRecordingAudioDevice,
                audioMode: root.recordAudioMode,
                filePath: root.currentRecordingPath,
                pid: recordProcess.processId === null || recordProcess.processId === undefined ? 0 : Number(recordProcess.processId),
                state: root.recordingState
            });
        }
        function stop(): void {
            root.stopActiveRecording();
        }
    }
    Timer {
        id: grabDelay
        interval: root.grabDelayMs
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
        target: Hyprland
        enabled: root.active && root.grabReady && root.activeScreen === null
        function onFocusedMonitorChanged() {
            root.selectFocusedMonitorAndGrab();
        }
    }
    Shortcut {
        enabled: root.active
        sequence: "Escape"
        onActivated: () => {
            if (root.recordingState === "recording") {
                root.stopActiveRecording();
                return;
            }
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
            if (root.recordingState === "recording")
                root.stopActiveRecording();
            else
                root.deactivate();
        }
    }
    Shortcut {
        enabled: root.active && root.recordingState !== "countdown" && root.recordingState !== "recording"
        sequence: "S"
        onActivated: root.toggleSaveMode()
    }
    Shortcut {
        enabled: root.active && root.recordingState !== "countdown" && root.recordingState !== "recording"
        sequence: "Tab"
        onActivated: root.toggleMode()
    }
    Timer {
        id: countdownTimer
        interval: root.countdownTickMs
        repeat: true
        running: false
        onTriggered: {
            if (root.countdownValue > 1) {
                root.countdownValue -= 1;
                countdownOverlay.pulse();
            } else {
                countdownTimer.stop();
                root.startRecording(root.recordingSelection);
            }
        }
    }
    Process {
        id: recordProcess
        property string stderrText: ""
        property string stdoutText: ""
        running: false
        stderr: StdioCollector {
            id: recordStderr
            waitForEnd: true
            onStreamFinished: recordProcess.stderrText = this.text
        }
        stdout: SplitParser {
            onRead: data => {
                const text = String(data || "").trim();
                if (text === "")
                    return;
                recordProcess.stdoutText = text;
                const match = text.match(/audio_device:(.+)$/i);
                if (match && match[1])
                    root.currentRecordingAudioDevice = String(match[1]).trim();
            }
        }
        // qmllint disable signal-handler-parameters
        onExited: function(code) {
            const reason = recordProcess.stderrText || recordProcess.stdoutText || `Command failed (code ${code})`;
            const hadRecording = root.recordingState === "recording";
            root.recordingState = "idle";
            root.sessionVisible = false;
            root.awaitingScreenConfirm = false;
            root.recordingSelection = null;
            root.syncRecordFlag();
            if (code === 0 || (code === 130 && hadRecording))
                root.notifyRecordingSuccess();
            else if (reason.trim() !== "")
                root.notifyRecordingFailure(reason);
            root.clearRecordingMetadata();
            root.deactivate();
        }
        // qmllint enable signal-handler-parameters
        onRunningChanged: {
            if (running) {
                recordProcess.stdoutText = "";
                recordProcess.stderrText = "";
                root.syncRecordFlag();
            }
            root.syncGlobalState();
        }
    }
    Loader {
        id: regionSelectorLoader
        active: root.sessionVisible && !root.initialFrozenGrabPending
        anchors.fill: parent
        sourceComponent: Src.RegionSelector {
            anchors.fill: parent
            borderRadius: 10.0
            dimOpacity: 0.6
            outlineThickness: 2.0
            visible: (root.mode === "region" && root.recordingState !== "recording") || root.awaitingScreenConfirm
            onClicked: (x, y) => {
                if (!root.awaitingScreenConfirm)
                    return;
                const insideControls = x >= controlWrapper.x && x <= (controlWrapper.x + controlWrapper.width) && y >= controlWrapper.y && y <= (controlWrapper.y + controlWrapper.height);
                if (insideControls)
                    return;
                root.awaitingScreenConfirm = false;
                if (!root.targetScreen)
                    return;
                if (root.recordingState === "selecting")
                    root.beginCountdownForSelection({ x: 0, y: 0, width: root.targetScreen.width, height: root.targetScreen.height });
                else
                    root.processScreenshot(0, 0, root.targetScreen.width, root.targetScreen.height);
            }
            onRegionSelected: (x, y, width, height) => {
                if (root.awaitingScreenConfirm) {
                    const insideControls = x >= controlWrapper.x && x <= (controlWrapper.x + controlWrapper.width) && y >= controlWrapper.y && y <= (controlWrapper.y + controlWrapper.height);
                    if (insideControls)
                        return;
                    root.awaitingScreenConfirm = false;
                    if (!root.targetScreen)
                        return;
                    if (root.recordingState === "selecting") {
                        root.beginCountdownForSelection({ x: 0, y: 0, width: root.targetScreen.width, height: root.targetScreen.height });
                    } else {
                        root.processScreenshot(0, 0, root.targetScreen.width, root.targetScreen.height);
                    }
                    return;
                }
                if (root.recordingState === "selecting") {
                    root.beginCountdownForSelection({ x, y, width, height });
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
            anchors.fill: parent
            borderRadius: 10.0
            dimOpacity: 0.6
            outlineThickness: 2.0
            visible: root.mode === "window" && root.recordingState !== "recording"
            windowTargets: root.currentWindowTargets
            onWindowSelected: target => {
                if (root.recordingState === "selecting") {
                    root.beginCountdownForSelection({
                        x: Number(target.x),
                        y: Number(target.y),
                        width: Number(target.width),
                        height: Number(target.height)
                    });
                    return;
                }
                root.processWindowScreenshot(target);
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
        audioMode: root.recordAudioMode
        windowModeAvailable: root.windowModeAvailable
        windowModeLoading: root.windowModeLoading
        onAudioModeSelected: selectedMode => root.setRecordAudioMode(selectedMode)
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
    Item { id: fullMaskItem; anchors.fill: parent; visible: false }
    Region { id: fullMask; item: fullMaskItem }
    Item { id: emptyMaskItem; width: 0; height: 0; visible: false }
    Region { id: emptyMask; item: emptyMaskItem }
}
