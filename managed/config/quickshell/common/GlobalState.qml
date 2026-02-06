pragma Singleton
import QtQml

QtObject {
    property bool leftPanelVisible: false
    property bool rightPanelVisible: false

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
}
