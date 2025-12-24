import QtQuick
import QtQuick.Layouts
import Quickshell
import "."
import "./modules"

PanelWindow {
  id: root
  property var modelData
  property var targetScreen: modelData

  screen: root.targetScreen
  anchors.top: true
  anchors.left: true
  anchors.right: true
  property int contentHeight: content.implicitHeight
    + Config.barPadding * 2
    + Config.moduleMarginTop
    + Config.moduleMarginBottom
  implicitHeight: Math.max(Config.barHeight, root.contentHeight)
  exclusiveZone: implicitHeight
  color: "transparent"

  Rectangle {
    anchors.fill: parent
    color: Config.barBackground
  }

  Item {
    id: content
    anchors.fill: parent
    anchors.margins: Config.barPadding

    implicitHeight: Math.max(
      leftRow.implicitHeight,
      centerRow.implicitHeight,
      rightRow.implicitHeight
    )

    RowLayout {
      id: leftRow
      anchors.left: parent.left
      anchors.top: parent.top
      spacing: Config.moduleSpacing

      StartMenuGroup {}
      WorkspaceGroup { screen: root.targetScreen }
    }

    RowLayout {
      id: centerRow
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      spacing: Config.moduleSpacing

      MprisModule {}
    }

    RowLayout {
      id: rightRow
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Config.moduleSpacing

      ControlsGroup {}
      WirelessGroup {}
      BatteryModule {}
      ClockModule {}
      PanelGroup { parentWindow: root }
    }
  }
}
