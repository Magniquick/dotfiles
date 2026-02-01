import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
  id: shellRoot

  PanelWindow {
    id: mockupWindow

    anchors {
      top: true
      left: true
      right: true
      bottom: true
    }

    color: "transparent"
    visible: true

    WlrLayershell.namespace: "quickshell:mockup"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.layer: WlrLayer.Overlay
    exclusiveZone: 0

    Shortcut {
      context: Qt.ApplicationShortcut
      sequence: "Escape"
      onActivated: Qt.quit()
    }

    Shortcut {
      context: Qt.ApplicationShortcut
      sequence: "q"
      onActivated: Qt.quit()
    }

    // Semi-transparent backdrop
    Rectangle {
      anchors.fill: parent
      color: Qt.alpha("#000000", 0.6)

      MouseArea {
        anchors.fill: parent
        onClicked: Qt.quit()
      }
    }

    // Centered mockup content
    HeaderMockup {
      anchors.centerIn: parent
    }
  }
}
