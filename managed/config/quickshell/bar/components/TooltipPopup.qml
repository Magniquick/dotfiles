import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."

Item {
  id: root
  property Item targetItem: null
  property Component contentComponent: null
  property bool open: false
  property bool hoverable: false
  property bool enabled: true
  property string title: ""
  property bool pinnable: false
  property bool pinned: false

  readonly property var window: targetItem ? targetItem.QsWindow.window : null
  property rect anchorRect: Qt.rect(0, 0, 0, 0)
  readonly property bool popupHovered: popupHover.hovered
  readonly property bool active: root.enabled
    && (root.open || (root.hoverable && root.popupHovered))

  function refreshAnchorRect() {
    if (!root.window || !root.targetItem)
      return
    root.anchorRect = root.window.itemRect(root.targetItem)
  }

  function updateAnchor() {
    root.refreshAnchorRect()
    if (popup.visible)
      popup.anchor.updateAnchor()
  }

  onOpenChanged: root.updateAnchor()
  onTargetItemChanged: root.updateAnchor()
  onEnabledChanged: {}

  Connections {
    target: root.targetItem
    function onXChanged() { root.updateAnchor() }
    function onYChanged() { root.updateAnchor() }
    function onWidthChanged() { root.updateAnchor() }
    function onHeightChanged() { root.updateAnchor() }
  }

  PopupWindow {
    id: popup
    property real reveal: root.active ? 1 : 0
    visible: root.window && reveal > 0.01
    color: "transparent"

    anchor {
      window: root.window
      rect.y: root.anchorRect.y + root.anchorRect.height + Config.tooltipOffset
      rect.x: root.anchorRect.x
      rect.width: root.anchorRect.width
      rect.height: 0
      edges: Edges.Top
      gravity: Edges.Bottom
      adjustment: PopupAdjustment.SlideX | PopupAdjustment.ResizeX
      margins {
        left: Config.tooltipBorderWidth
        right: Config.tooltipBorderWidth
      }
    }

    implicitWidth: body.implicitWidth
    implicitHeight: body.implicitHeight

    onImplicitWidthChanged: root.updateAnchor()
    onImplicitHeightChanged: root.updateAnchor()

    Behavior on reveal {
      NumberAnimation {
        duration: Config.motion.duration.medium
        easing.type: Config.motion.easing.emphasized
      }
    }

    Item {
      id: body
      implicitWidth: layout.implicitWidth + Config.tooltipPadding * 2
      implicitHeight: layout.implicitHeight + Config.tooltipPadding * 2
      opacity: popup.reveal
      scale: 0.96 + (0.04 * popup.reveal)
      y: Config.motion.distance.medium * (1 - popup.reveal)
      transformOrigin: Item.Top

      Rectangle {
        id: panel
        anchors.fill: parent
        color: Config.tooltipBackground
        radius: Config.tooltipRadius
        antialiasing: true
        clip: true
      }

      Rectangle {
        id: panelBorder
        x: 0.5
        y: 0.5
        width: Math.max(0, panel.width - 1)
        height: Math.max(0, panel.height - 1)
        radius: Math.max(0, panel.radius - 0.5)
        color: "transparent"
        border.width: 1
        border.color: Config.tooltipBorder
        antialiasing: true
      }

      Rectangle {
        anchors.left: panel.left
        anchors.right: panel.right
        anchors.top: panel.top
        height: headerRow.visible ? (headerRow.implicitHeight + Config.tooltipPadding) : 0
        radius: Config.tooltipRadius
        color: "transparent"
      }

      ColumnLayout {
        id: layout
        anchors.fill: panel
        anchors.margins: Config.tooltipPadding
        spacing: Config.space.sm

        RowLayout {
          id: headerRow
          spacing: Config.space.sm
          visible: root.title !== "" || root.pinnable

          Rectangle {
            id: pulse
            width: Config.space.sm
            height: Config.space.sm
            radius: Config.shape.corner.xs
            color: Config.color.primary
            opacity: 0.9
            Layout.alignment: Qt.AlignVCenter

            SequentialAnimation on scale {
              running: popup.reveal > 0.01
              loops: Animation.Infinite
              NumberAnimation {
                to: 1.25
                duration: Config.motion.duration.pulse
                easing.type: Config.motion.easing.standard
              }
              NumberAnimation {
                to: 1.0
                duration: Config.motion.duration.pulse
                easing.type: Config.motion.easing.standard
              }
            }
          }

          Text {
            text: root.title
            visible: root.title !== ""
            color: Config.textColor
            font.family: Config.fontFamily
            font.pixelSize: Config.type.titleSmall.size
            font.weight: Config.type.titleSmall.weight
            Layout.fillWidth: true
            elide: Text.ElideRight
          }

          Item {
            visible: root.title === ""
            Layout.fillWidth: true
          }

          Item {
            visible: root.pinnable
            Layout.preferredWidth: 0
            Layout.preferredHeight: 0
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Config.color.outline
          opacity: 0.18
          visible: headerRow.visible
        }

        Loader {
          id: contentLoader
          sourceComponent: root.contentComponent
          active: true
        }
      }

      HoverHandler {
        id: popupHover
        target: body
        enabled: root.hoverable
      }
    }
  }
}
