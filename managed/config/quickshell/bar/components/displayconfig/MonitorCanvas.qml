pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.bar

Rectangle {
  id: root

  property bool dragActive: false

  implicitHeight: 336
  radius: Config.shape.corner.md
  color: Qt.tint(Config.barPopupSurface, Qt.alpha(Config.color.surface_container_highest, 0.72))
  border.width: 1
  border.color: Qt.alpha(Config.color.outline_variant, 0.6)

  readonly property var names: HyprDisplayConfigState.outputNames.filter(name => {
    const output = HyprDisplayConfigState.getOutput(name);
    return output && !output.disabled;
  })
  readonly property var bounds: HyprDisplayConfigState.boundsForNames(names)

  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Config.space.md
    spacing: Config.space.xs

    Row {
      spacing: Config.space.sm

      Text {
        color: Config.color.primary
        font.family: Config.iconFontFamily
        font.pixelSize: Config.type.titleSmall.size
        renderType: Text.NativeRendering
        text: "󰆾"
      }

      Text {
        color: Config.color.on_surface
        font.family: Config.fontFamily
        font.pixelSize: Config.type.labelLarge.size
        font.weight: Config.type.labelLarge.weight
        renderType: Text.NativeRendering
        text: "Drag displays in this preview to reposition them"
      }
    }

    Text {
      color: Config.color.on_surface_variant
      font.family: Config.fontFamily
      font.pixelSize: Config.type.bodySmall.size
      renderType: Text.NativeRendering
      text: "Grab a monitor card and move it. The X/Y fields below update to match."
    }
  }

  Item {
    id: viewport

    anchors.fill: parent
    anchors.leftMargin: Config.space.lg
    anchors.rightMargin: Config.space.lg
    anchors.bottomMargin: Config.space.lg
    anchors.topMargin: 68

    readonly property real scaleFactor: {
      const widthScale = root.bounds.width > 0 ? width / root.bounds.width : 0.1;
      const heightScale = root.bounds.height > 0 ? height / root.bounds.height : 0.1;
      return Math.max(0.08, Math.min(widthScale, heightScale));
    }
    readonly property real offsetX: (width - root.bounds.width * scaleFactor) / 2 - root.bounds.minX * scaleFactor
    readonly property real offsetY: (height - root.bounds.height * scaleFactor) / 2 - root.bounds.minY * scaleFactor

    Repeater {
      model: root.names

      delegate: Rectangle {
        id: monitorRect

        required property string modelData
        readonly property var output: HyprDisplayConfigState.getOutput(modelData)
        readonly property var size: HyprDisplayConfigState.outputLogicalSize(output)
        property bool dragging: false

        x: dragging ? x : viewport.offsetX + (Number(output.x || 0) * viewport.scaleFactor)
        y: dragging ? y : viewport.offsetY + (Number(output.y || 0) * viewport.scaleFactor)
        width: Math.max(92, size.width * viewport.scaleFactor)
        height: Math.max(60, size.height * viewport.scaleFactor)
        z: dragging ? 10 : 1
        radius: Config.shape.corner.sm
        color: monitorRect.dragging
          ? Qt.tint(Config.color.primary_container, Qt.alpha(Config.color.primary, 0.18))
          : Qt.tint(Config.barPopupSurface, Qt.alpha(Config.color.surface_container, 0.55))
        border.width: 1
        border.color: dragArea.containsMouse || monitorRect.dragging
          ? Config.color.primary
          : Qt.alpha(Config.color.outline_variant, 0.72)

        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: Config.space.sm
          spacing: Config.space.xs

          Text {
            color: Config.color.on_surface
            elide: Text.ElideRight
            font.family: Config.fontFamily
            font.pixelSize: Config.type.labelLarge.size
            font.weight: Config.type.labelLarge.weight
            renderType: Text.NativeRendering
            text: monitorRect.modelData
          }

          Text {
            color: Config.color.on_surface_variant
            elide: Text.ElideRight
            font.family: Config.fontFamily
            font.pixelSize: Config.type.labelSmall.size
            renderType: Text.NativeRendering
            text: HyprDisplayConfigState.modeLabel(output.mode) + " • " + Number(output.scale || 1).toFixed(2) + "x"
          }
        }

        MouseArea {
          id: dragArea

          anchors.fill: parent
          hoverEnabled: true
          cursorShape: monitorRect.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
          drag.target: monitorRect
          drag.axis: Drag.XAndYAxis
          drag.threshold: 0

          onPressed: function() {
            root.dragActive = true;
            monitorRect.dragging = true;
          }
          onReleased: function() {
            root.dragActive = false;
            const outputX = (monitorRect.x - viewport.offsetX) / viewport.scaleFactor;
            const outputY = (monitorRect.y - viewport.offsetY) / viewport.scaleFactor;
            monitorRect.dragging = false;
            HyprDisplayConfigState.setPosition(monitorRect.modelData, outputX, outputY);
          }
          onCanceled: {
            root.dragActive = false;
            monitorRect.dragging = false;
          }
        }
      }
    }
  }
}
