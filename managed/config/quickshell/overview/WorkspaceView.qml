pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell.Hyprland
import Quickshell.Wayland
import "../common" as Common

Rectangle {
  id: root

  required property int tileIndex
  required property Item parentWindow
  property bool livePreviews: false
  property int refreshSerial: 0

  property HyprlandWorkspace workspace: Hyprland.workspaces.values.find(ws => ws.id === (tileIndex + 1)) || null
  readonly property var monitorIpc: workspace && workspace.monitor && workspace.monitor.lastIpcObject
    ? workspace.monitor.lastIpcObject
    : null
  readonly property var reservedEdges: monitorIpc && monitorIpc.reserved ? monitorIpc.reserved : [0, 0, 0, 0]
  readonly property real reservedLeft: reservedEdges.length > 0 ? Number(reservedEdges[0]) || 0 : 0
  readonly property real reservedTop: reservedEdges.length > 1 ? Number(reservedEdges[1]) || 0 : 0
  readonly property real reservedRight: reservedEdges.length > 2 ? Number(reservedEdges[2]) || 0 : 0
  readonly property real reservedBottom: reservedEdges.length > 3 ? Number(reservedEdges[3]) || 0 : 0
  readonly property real sourceWidth: {
    if (!workspace || !workspace.monitor)
      return 0;
    return Math.max(1, (workspace.monitor.width / workspace.monitor.scale) - reservedLeft - reservedRight);
  }
  readonly property real sourceHeight: {
    if (!workspace || !workspace.monitor)
      return 0;
    return Math.max(1, (workspace.monitor.height / workspace.monitor.scale) - reservedTop - reservedBottom);
  }
  readonly property real scaleFactor: {
    if (!workspace || !workspace.monitor || viewport.width <= 0 || viewport.height <= 0)
      return -1;
    return Math.max(sourceWidth / viewport.width, sourceHeight / viewport.height);
  }
  readonly property real contentWidth: scaleFactor > 0 ? (sourceWidth / scaleFactor) : 0
  readonly property real contentHeight: scaleFactor > 0 ? (sourceHeight / scaleFactor) : 0
  readonly property real contentOffsetX: Math.max(0, (viewport.width - contentWidth) / 2)
  readonly property real contentOffsetY: Math.max(0, (viewport.height - contentHeight) / 2)

  visible: true
  color: Qt.alpha(Common.Config.color.surface_container_low, 0.78)
  radius: Common.Config.shape.corner.lg
  border.width: workspace && workspace.active ? 2 : 1
  border.color: workspace && workspace.active
    ? Common.Config.color.primary
    : Qt.alpha(Common.Config.color.outline_variant, 0.9)

  onRefreshSerialChanged: {
    if (!root.livePreviews)
      refreshTimer.restart();
  }

  Timer {
    id: refreshTimer
    interval: 140
    repeat: false

    onTriggered: {
      for (let i = 0; i < viewportRepeater.count; ++i) {
        const item = viewportRepeater.itemAt(i);
        // qmllint disable missing-property
        const captureFrame = item ? item["captureFrame"] : null;
        // qmllint enable missing-property
        if (typeof captureFrame === "function")
          captureFrame.call(item);
      }
    }
  }

  Item {
    id: viewport
    anchors.fill: parent
    anchors.margins: root.border.width
    clip: true

    layer.enabled: true
    layer.effect: OpacityMask {
      maskSource: Rectangle {
        width: viewport.width
        height: viewport.height
        radius: Math.max(0, root.radius - root.border.width)
      }
    }

    Repeater {
      id: viewportRepeater
      model: root.workspace ? root.workspace.toplevels : []

      ScreencopyView {
        id: preview

        required property HyprlandToplevel modelData
        required property int index

        readonly property var ipc: modelData && modelData.lastIpcObject ? modelData.lastIpcObject : null
        readonly property string address: ipc && ipc.address ? ipc.address : ""
        readonly property int workspaceId: root.workspace ? root.workspace.id : -1

        // qmllint disable unresolved-type
        captureSource: modelData && modelData["wayland"] ? modelData["wayland"] : null
        // qmllint enable unresolved-type
        live: root.livePreviews && root.visible && !!captureSource && !dragHandler.active
        x: (ipc && ipc.at && root.workspace && root.workspace.monitor && root.scaleFactor > 0)
          ? (root.contentOffsetX + ((ipc.at[0] - root.workspace.monitor.x - root.reservedLeft) / root.scaleFactor))
          : 0
        y: (ipc && ipc.at && root.workspace && root.workspace.monitor && root.scaleFactor > 0)
          ? (root.contentOffsetY + ((ipc.at[1] - root.workspace.monitor.y - root.reservedTop) / root.scaleFactor))
          : 0
      width: (ipc && ipc.size && root.scaleFactor > 0) ? (ipc.size[0] / root.scaleFactor) : 0
      height: (ipc && ipc.size && root.scaleFactor > 0) ? (ipc.size[1] / root.scaleFactor) : 0
        z: dragHandler.active ? 10 : 1

        DragHandler {
          id: dragHandler
          target: preview

          onActiveChanged: {
            if (!active)
              preview.Drag.drop();
          }
        }

        Drag.active: dragHandler.active
        Drag.source: preview
        Drag.supportedActions: Qt.MoveAction
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2

        states: [
          State {
            when: dragHandler.active
            ParentChange {
              target: preview
              parent: root.parentWindow
            }
          }
        ]
      }
    }
  }

  Text {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.margins: Common.Config.space.sm
    text: String(root.tileIndex + 1)
    color: root.workspace && root.workspace.active
      ? Common.Config.color.primary
      : Common.Config.color.on_surface_variant
    font.family: Common.Config.fontFamily
    font.pixelSize: Common.Config.type.titleMedium.size
    font.bold: true
    renderType: Text.NativeRendering
    z: 3
  }

  MouseArea {
    anchors.fill: parent
    enabled: !!root.workspace
    z: 4
    onClicked: {
      if (root.workspace && root.workspace.activate)
        root.workspace.activate();
    }
  }
}
