import QtQuick
import QtQml
import Quickshell
import "../theme"

Row {
  id: root
  spacing: Theme.spacing
  property var parentWindow: QsWindow.window
  property var tray: null
  property bool available: false

  visible: available

  function createTray() {
    const src = "import Quickshell.Services.SystemTray; SystemTray {}";
    const comp = Qt.createComponent(src);
    if (comp.status === Component.Ready) {
      tray = comp.createObject(root);
      available = !!tray;
    } else {
      comp.statusChanged.connect(function(status) {
        if (status === Component.Ready) {
          tray = comp.createObject(root);
          available = !!tray;
        }
      });
    }
  }

  Component.onCompleted: createTray()

  Repeater {
    model: tray && tray.items ? tray.items : []

    delegate: Item {
      required property var modelData
      width: 20
      height: Theme.barHeight

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: modelData.activate()
        onPressed: (event) => {
          if (event.button === Qt.RightButton && modelData.hasMenu) {
            modelData.display(parentWindow, mouseX, mouseY);
          }
        }
      }

      Image {
        anchors.centerIn: parent
        source: modelData.icon
        fillMode: Image.PreserveAspectFit
        sourceSize.width: 18
        sourceSize.height: 18
        smooth: true
      }
    }
  }
}
