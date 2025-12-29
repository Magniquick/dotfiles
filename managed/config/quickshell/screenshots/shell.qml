import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls

ShellRoot {
    id: root

    readonly property var palette: ColorPalette.palette
    readonly property var screenshotsScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    property bool screenshotsVisible: true

    function hideScreenshots() {
        screenshotsVisible = false;
    }
    function showScreenshots() {
        screenshotsVisible = true;
    }
    function toggleScreenshots() {
        screenshotsVisible = !screenshotsVisible;
    }

    IpcHandler {
        function hide(): void {
            root.hideScreenshots();
        }
        function show(): void {
            root.showScreenshots();
        }
        function toggle(): void {
            root.toggleScreenshots();
        }

        target: "screenshots"
    }
    ScreenshotsPill {
        id: screenshotsPill

        colors: palette
        targetScreen: screenshotsScreen
        visible: screenshotsVisible && screenshotsScreen

        onRequestClose: root.hideScreenshots()
    }
}
