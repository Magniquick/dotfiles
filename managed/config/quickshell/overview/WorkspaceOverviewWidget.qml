pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../common" as Common

Item {
  id: root

  required property Item dragLayer
  property bool livePreviews: false
  property var refreshSerials: ({})
  property var focusedScreen: Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) || null
  property HyprlandMonitor focusedMonitor: Hyprland.focusedMonitor
  property real spacing: Common.Config.space.sm
  property int columns: 3
  property int rows: 3
  property real windowAspectRatio: 1270 / 672
  property real monitorWidth: focusedMonitor ? (focusedMonitor.width / focusedMonitor.scale) : 1600
  property real monitorHeight: focusedMonitor ? (focusedMonitor.height / focusedMonitor.scale) : 900
  property real maxContentWidth: monitorWidth * 0.92
  property real maxContentHeight: monitorHeight * 0.72
  property real widthLimitedTileWidth: (maxContentWidth - spacing * (columns + 1)) / columns
  property real heightLimitedTileHeight: (maxContentHeight - spacing * (rows + 1)) / rows
  property real tileWidth: Math.max(120, Math.min(widthLimitedTileWidth, heightLimitedTileHeight * windowAspectRatio))
  property real tileHeight: tileWidth / windowAspectRatio
  property real contentWidth: tileWidth * columns + spacing * (columns + 1)
  property real contentHeight: tileHeight * rows + spacing * (rows + 1)

  implicitWidth: contentWidth
  implicitHeight: contentHeight

  function refreshSerialForWorkspace(workspaceId) {
    if (!(workspaceId > 0))
      return 0;
    const value = root.refreshSerials[String(workspaceId)];
    return typeof value === "number" ? value : 0;
  }

  function bumpWorkspaceRefresh(workspaceId) {
    if (!(workspaceId > 0))
      return;
    const key = String(workspaceId);
    const next = refreshSerialForWorkspace(workspaceId) + 1;
    root.refreshSerials = Object.assign({}, root.refreshSerials, { [key]: next });
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.alpha(Common.Config.color.surface_container_low, 0.97)
    radius: Common.Config.shape.corner.xl
    border.width: 1
    border.color: Qt.alpha(Common.Config.color.outline_variant, 0.88)

    GridLayout {
      id: overviewLayout
      anchors.fill: parent
      anchors.margins: root.spacing
      columns: root.columns
      rows: root.rows
      rowSpacing: root.spacing
      columnSpacing: root.spacing

      Repeater {
        model: root.rows * root.columns

        delegate: WorkspaceView {
          id: workspaceTile
          required property int index

          tileIndex: index
          parentWindow: root.dragLayer
          livePreviews: root.livePreviews
          refreshSerial: root.refreshSerialForWorkspace(index + 1)
          implicitWidth: root.tileWidth
          implicitHeight: root.tileHeight

          DropArea {
            anchors.fill: parent

            onDropped: function(drop) {
              const source = drop.source || null;
              // qmllint disable missing-property
              const address = source && source["address"] ? String(source["address"]) : "";
              const sourceWorkspaceId = source && typeof source["workspaceId"] === "number"
                ? source["workspaceId"]
                : -1;
              // qmllint enable missing-property
              const targetWorkspaceId = workspaceTile.index + 1;
              if (address === "")
                return;

              Hyprland.dispatch("movetoworkspacesilent " + String(targetWorkspaceId) + ", address:" + address);
              Hyprland.refreshWorkspaces();
              Hyprland.refreshMonitors();
              Hyprland.refreshToplevels();
              root.bumpWorkspaceRefresh(sourceWorkspaceId);
              root.bumpWorkspaceRefresh(targetWorkspaceId);
            }
          }
        }
      }
    }
  }
}
