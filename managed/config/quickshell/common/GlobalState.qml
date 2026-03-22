pragma Singleton
import QtQml

QtObject {
    property var hyprQuickshotController: null
    property bool hyprQuickshotVisible: false
    property var hyprQuickshotScreen: null
    property int notificationCount: 0
    property bool notificationDnd: false
    property bool screenRecordingActive: false
    property string screenRecordingAudioDevice: ""
    property string screenRecordingAudioMode: "off"
    property string screenRecordingPath: ""
    property int screenRecordingPid: 0
    property string screenRecordingState: "idle"
    property bool leftPanelVisible: false
    property bool rightPanelVisible: false
    property bool overviewVisible: false
    property bool idleSleepInhibited: false
    // -2 = off, -1 = indefinite, positive = timed minutes preset.
    property int idleSleepInhibitModeMinutes: -2
    // Unix epoch in milliseconds; 0 means no timed expiry.
    property double idleSleepInhibitUntilMs: 0

    // Remember which output the panel should appear on. Callers should pass a
    // `Screen` object (typically `root.QsWindow.window.screen`).
    property var leftPanelScreen: null
    property var rightPanelScreen: null
    property var overviewScreen: null

    function toggleLeftPanel(screen) {
        if (screen) {
            leftPanelScreen = screen;
        }
        overviewVisible = false;
        leftPanelVisible = !leftPanelVisible;
    }

    function toggleRightPanel(screen) {
        if (screen) {
            rightPanelScreen = screen;
        }
        overviewVisible = false;
        rightPanelVisible = !rightPanelVisible;
    }

    function closeOverview() {
        overviewVisible = false;
    }

    function openOverview(screen) {
        if (screen)
            overviewScreen = screen;
        leftPanelVisible = false;
        rightPanelVisible = false;
        overviewVisible = true;
    }

    function toggleOverview(screen) {
        if (overviewVisible) {
            overviewVisible = false;
            return;
        }

        openOverview(screen);
    }

    function setNotificationDnd(enabled) {
        notificationDnd = !!enabled;
    }

    function toggleNotificationDnd() {
        notificationDnd = !notificationDnd;
    }

    function clearSleepInhibit() {
        idleSleepInhibited = false;
        idleSleepInhibitModeMinutes = -2;
        idleSleepInhibitUntilMs = 0;
    }

    function registerHyprQuickshot(controller) {
        hyprQuickshotController = controller || null;
    }

    function resetScreenRecordingState() {
        screenRecordingActive = false;
        screenRecordingAudioDevice = "";
        screenRecordingAudioMode = "off";
        screenRecordingPath = "";
        screenRecordingPid = 0;
        screenRecordingState = "idle";
    }

    function setHyprQuickshotVisible(visible, screen) {
        hyprQuickshotVisible = !!visible;
        if (screen)
            hyprQuickshotScreen = screen;
    }

    function toggleHyprQuickshot(screen) {
        if (screen)
            hyprQuickshotScreen = screen;
        hyprQuickshotVisible = !hyprQuickshotVisible;
    }

    function stopScreenRecording() {
        if (hyprQuickshotController && typeof hyprQuickshotController.stopActiveRecording === "function")
            hyprQuickshotController.stopActiveRecording();
    }

    function setSleepInhibitIndefinite() {
        idleSleepInhibited = true;
        idleSleepInhibitModeMinutes = -1;
        idleSleepInhibitUntilMs = 0;
    }

    function setSleepInhibitForMinutes(minutes) {
        const parsedMinutes = Number(minutes);
        if (!(parsedMinutes > 0)) {
            clearSleepInhibit();
            return;
        }

        idleSleepInhibited = true;
        idleSleepInhibitModeMinutes = Math.round(parsedMinutes);
        idleSleepInhibitUntilMs = Date.now() + idleSleepInhibitModeMinutes * 60 * 1000;
    }
}
