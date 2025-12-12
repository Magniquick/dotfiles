import QtQuick
import Quickshell
import "modules"
import "theme"

Scope {
  id: root

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData

      anchors {
        top: true
        left: true
        right: true
      }

      color: "transparent"
      implicitHeight: Theme.barHeight + Theme.topMargin

      Rectangle {
        anchors.fill: parent
        color: "transparent"

        Item {
          anchors.fill: parent
          anchors.leftMargin: Theme.edgeMargin
          anchors.rightMargin: Theme.edgeMargin
          anchors.topMargin: Theme.topMargin

          Row {
            id: leftRow
            anchors {
              left: parent.left
              verticalCenter: parent.verticalCenter
            }
            spacing: Theme.spacing

            StartMenuGroup { }
            WorkspaceGroup { }
          }

          Row {
            id: centerRow
            anchors.centerIn: parent
            spacing: Theme.spacing
            BarPill { MprisModule { } }
          }

          Row {
            id: rightRow
            anchors {
              right: parent.right
              verticalCenter: parent.verticalCenter
            }
            spacing: Theme.spacing

            ControlsGroup { }
            WirelessGroup { }
            BarPill { BatteryModule { } }
            BarPill { ClockModule { } }
            PanelGroup { }
          }
        }
      }
    }
  }
}
