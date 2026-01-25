import Quickshell
import Quickshell.Io
import QtQuick
import "./common" as Common

ShellRoot {
    id: root

    readonly property var colors: Common.Config.color
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

        colors: root.colors
        targetScreen: root.screenshotsScreen
        visible: root.screenshotsVisible && root.screenshotsScreen

        onRequestClose: root.hideScreenshots()
    }
}
