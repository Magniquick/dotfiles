pragma Singleton
import QtQml

QtObject {
    property bool leftPanelVisible: false
    property bool rightPanelVisible: false
    property bool idleSleepInhibited: false
    // -2 = off, -1 = indefinite, positive = timed minutes preset.
    property int idleSleepInhibitModeMinutes: -2
    // Unix epoch in milliseconds; 0 means no timed expiry.
    property double idleSleepInhibitUntilMs: 0

    // Remember which output the panel should appear on. Callers should pass a
    // `Screen` object (typically `root.QsWindow.window.screen`).
    property var leftPanelScreen: null
    property var rightPanelScreen: null

    function toggleLeftPanel(screen) {
        if (screen) {
            leftPanelScreen = screen;
        }
        leftPanelVisible = !leftPanelVisible;
    }

    function toggleRightPanel(screen) {
        if (screen) {
            rightPanelScreen = screen;
        }
        rightPanelVisible = !rightPanelVisible;
    }

    function clearSleepInhibit() {
        idleSleepInhibited = false;
        idleSleepInhibitModeMinutes = -2;
        idleSleepInhibitUntilMs = 0;
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
