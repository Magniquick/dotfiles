import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls

ShellRoot {
  id: root

  property bool screenshotsVisible: true
  readonly property var screenshotsScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  readonly property var palette: ColorPalette.palette

  function toggleScreenshots() {
    screenshotsVisible = !screenshotsVisible
  }

  function showScreenshots() {
    screenshotsVisible = true
  }

  function hideScreenshots() {
    screenshotsVisible = false
  }

  IpcHandler {
    target: "screenshots"
    function toggle(): void { root.toggleScreenshots() }
    function show(): void { root.showScreenshots() }
    function hide(): void { root.hideScreenshots() }
  }


  ScreenshotsPill {
    id: screenshotsPill
    visible: screenshotsVisible && screenshotsScreen
    targetScreen: screenshotsScreen
    colors: palette
    onRequestClose: root.hideScreenshots()
  }

}
