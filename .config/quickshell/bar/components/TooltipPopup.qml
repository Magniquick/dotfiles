import ".."
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell._Window
import "../../common" as Common
import "../../common/materialkit" as MK

Item {
  id: root

  readonly property bool active: root.enabled && (root.open || root.pinned || (root.hoverable && root.popupHovered))
  readonly property int morphDuration: Math.round(280 * Config.motionScale)
  readonly property int revealCloseDuration: Math.round(240 * Config.motionScale)
  readonly property int revealOpenDuration: Math.round(320 * Config.motionScale)
  property rect anchorRect: Qt.rect(0, 0, 0, 0)
  property bool autoScroll: true
  // Either a URL string (opened via Qt) or an argv array.
  // Do not pass a shell string here; it will be ignored for safety.
  property var browserLink: ""
  property Component contentComponent: null
  property bool hoverable: false
  property int maximumHeight: 0
  property bool open: false
  property bool pinnable: false
  property bool pinned: false
  readonly property bool popupHovered: popupHover.hovered
  property bool refreshing: false
  property bool showBrowserIcon: false
  property bool showRefreshIcon: false
  property bool showScrollIndicator: true
  property string subtitle: ""
  property Item targetItem: null
  property var targetWindow: null
  property string title: ""
  readonly property var contentItem: contentLoader.item
  readonly property bool visualActive: popup.visible
  readonly property var window: root.targetWindow || (targetItem ? targetItem.QsWindow.window : null)
  property bool _anchorUpdatePending: false

  signal refreshRequested

  function _looksLikeUrl(s) {
    if (!s)
      return false
    const t = String(s).trim();
    // Accept "scheme://..." and also "scheme:" (mailto:, about:, etc).
    return t.indexOf("://") !== -1 || /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(t)
  }

  function _openBrowserLink() {
    if (Array.isArray(root.browserLink)) {
      if (root.browserLink.length === 0)
        return
      Common.ProcessHelper.execDetached(root.browserLink)
      return
    }

    if (typeof root.browserLink !== "string")
      return
    const link = root.browserLink.trim()
    if (!link)
      return
    if (!root._looksLikeUrl(link)) {
      console.warn("[TooltipPopup] browserLink must be a URL string or argv array; refusing to exec shell string:", link)
      return
    }

    Qt.openUrlExternally(link)
  }

  function refreshAnchorRect() {
    if (!root.window || !root.targetItem)
      return
    const nextRect = root.window.itemRect(root.targetItem)
    if (nextRect.x === root.anchorRect.x && nextRect.y === root.anchorRect.y && nextRect.width === root.anchorRect.width && nextRect.height === root.anchorRect.height)
      return
    root.anchorRect = nextRect
  }
  function _updateAnchorNow() {
    root.refreshAnchorRect()
    if (popup.visible)
      popup.anchor.updateAnchor()
  }
  function updateAnchor() {
    if (root._anchorUpdatePending)
      return
    root._anchorUpdatePending = true
    Qt.callLater(() => {
      root._anchorUpdatePending = false
      root._updateAnchorNow()
    })
  }

  onOpenChanged: root.updateAnchor()
  onTargetItemChanged: root.updateAnchor()

  Connections {
    function onHeightChanged() {
      root.updateAnchor()
    }
    function onWidthChanged() {
      root.updateAnchor()
    }
    function onXChanged() {
      root.updateAnchor()
    }
    function onYChanged() {
      root.updateAnchor()
    }

    target: root.targetItem
  }
  PopupWindow {
    id: popup

    property real reveal: root.active ? 1 : 0
    Component.onCompleted: {
      if (root.active) {
        popup.reveal = 1
      } else {
        popup.reveal = 0
      }
    }
    Connections {
      target: root
      function onActiveChanged() {
        popup.reveal = root.active ? 1 : 0
      }
    }

    onVisibleChanged: {
      if (!visible)
        body.resetWindowSize()
    }

    color: "transparent"
    implicitHeight: body.windowHeight
    implicitWidth: body.targetImplicitWidth
    visible: reveal > 0.01

    Behavior on reveal {
      NumberAnimation {
        id: revealAnimation
        // Snap open when a tooltip is reopened during the dismiss animation.
        duration: {
          if (!root.active)
            return root.revealCloseDuration
          if (popup.reveal > 0 && popup.reveal < 1)
            return 0
          return root.revealOpenDuration
        }
        easing.type: root.active ? Easing.OutCubic : Easing.InOutCubic
      }
    }

    anchor {
      adjustment: PopupAdjustment.SlideX | PopupAdjustment.ResizeX
      edges: Edges.Top
      gravity: Edges.Bottom
      rect.height: 0
      rect.width: root.anchorRect.width
      rect.x: root.anchorRect.x
      rect.y: root.anchorRect.y + root.anchorRect.height + Config.tooltipOffset
      window: root.window

      margins {
        left: Config.tooltipBorderWidth
        right: Config.tooltipBorderWidth
      }
    }
    Item {
      id: body

      readonly property real targetImplicitHeight: {
        const naturalHeight = layout.implicitHeight + Config.tooltipPadding * 2
        if (root.maximumHeight > 0) {
          return Math.min(naturalHeight, root.maximumHeight)
        }
        return naturalHeight
      }
      readonly property real targetImplicitWidth: layout.implicitWidth + Config.tooltipPadding * 2
      property real displayHeight: targetImplicitHeight
      property real displayWidth: targetImplicitWidth
      property real windowHeight: targetImplicitHeight

      function updateWindowSize() {
        windowHeight = Math.max(windowHeight, targetImplicitHeight)
      }

      function resetWindowSize() {
        windowHeight = targetImplicitHeight
      }

      clip: true
      height: displayHeight
      implicitHeight: displayHeight
      implicitWidth: displayWidth
      opacity: popup.reveal
      scale: 0.86 + (0.14 * popup.reveal)
      transformOrigin: Item.Top
      width: displayWidth
      x: Math.min(0, (targetImplicitWidth - displayWidth) / 2)
      y: Math.round(18 * Config.motionScale) * (1 - popup.reveal)

      Behavior on displayHeight {
        NumberAnimation {
          duration: root.morphDuration
          easing.type: Easing.OutCubic
        }
      }

      Behavior on displayWidth {
        NumberAnimation {
          duration: root.morphDuration
          easing.type: Easing.OutCubic
        }
      }

      onTargetImplicitHeightChanged: body.updateWindowSize()
      onTargetImplicitWidthChanged: body.updateWindowSize()

      Rectangle {
        id: panel

        anchors.fill: parent
        antialiasing: true
        clip: true
        color: Config.barPopupSurface
        radius: Config.tooltipRadius
      }
      Rectangle {
        id: panelBorder

        antialiasing: true
        border.color: Config.color.outline_variant
        border.width: 1
        color: "transparent"
        height: Math.max(0, panel.height - 1)
        radius: Math.max(0, panel.radius - 0.5)
        width: Math.max(0, panel.width - 1)
        x: 0.5
        y: 0.5
      }
      Rectangle {
        anchors.left: panel.left
        anchors.right: panel.right
        anchors.top: panel.top
        color: "transparent"
        height: headerRow.visible ? (headerRow.implicitHeight + Config.tooltipPadding) : 0
        radius: Config.tooltipRadius
      }
      ColumnLayout {
        id: layout

        anchors.fill: panel
        anchors.margins: Config.tooltipPadding
        spacing: Config.space.sm

        RowLayout {
          id: headerRow

          spacing: Config.space.sm
          // Global no-op for module popup title header ("Bluetooth", etc).
          visible: false

          Rectangle {
            id: pulse

            Layout.alignment: Qt.AlignVCenter
            color: Config.color.primary
            Layout.preferredHeight: Config.space.sm
            Layout.preferredWidth: Config.space.sm
            implicitHeight: Config.space.sm
            implicitWidth: Config.space.sm
            opacity: 0.9
            radius: Config.shape.corner.xs
            visible: true

            SequentialAnimation on scale {
              alwaysRunToEnd: false
              loops: Animation.Infinite
              running: popup.visible && pulse.visible && Config.tooltipPulseAnimationEnabled

              NumberAnimation {
                duration: Config.motion.duration.pulse
                easing.type: Config.motion.easing.standard
                to: 1.25
              }
              NumberAnimation {
                duration: Config.motion.duration.pulse
                easing.type: Config.motion.easing.standard
                to: 1
              }
            }
          }
          Text {
            color: Config.color.on_surface
            elide: Text.ElideRight
            font.family: Config.fontFamily
            font.pixelSize: Config.type.titleSmall.size
            font.weight: Config.type.titleSmall.weight
            text: root.title
            visible: root.title !== ""
          }
          Item {
            Layout.fillWidth: true
          }

          // Browser icon
          Item {
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: browserIconText.implicitHeight
            implicitWidth: browserIconText.implicitWidth
            visible: root.showBrowserIcon && ((Array.isArray(root.browserLink) && root.browserLink.length > 0) || (typeof root.browserLink === "string" && root.browserLink.trim() !== ""))

            Text {
              id: browserIconText

              color: Config.color.on_surface_variant
              font.family: Config.iconFontFamily
              font.pixelSize: Config.type.labelSmall.size
              opacity: browserIconHover.hovered ? 0.9 : 0.6
              text: "󰖟"
            }
            HoverHandler {
              id: browserIconHover

              cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
              onTapped: {
                root._openBrowserLink()
              }
            }
          }

          // Refresh icon on the right with hover tooltip
          Item {
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: refreshIconText.implicitHeight
            implicitWidth: refreshIconText.implicitWidth
            visible: root.showRefreshIcon

            Text {
              id: refreshIconText

              color: Config.color.on_surface_variant
              font.family: Config.iconFontFamily
              font.pixelSize: Config.type.labelSmall.size
              opacity: refreshIconHover.hovered ? 0.9 : 0.6
              text: "󰑐"
            }
            HoverHandler {
              id: refreshIconHover

              cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
              onTapped: root.refreshRequested()
            }

            // Hover tooltip for refresh time
            Rectangle {
              anchors.right: parent.left
              anchors.rightMargin: Config.space.xs
              anchors.verticalCenter: parent.verticalCenter
              border.color: Config.color.outline
              border.width: 1
              color: Config.color.surface_container_high
              implicitHeight: refreshTimeText.implicitHeight + Config.space.xs * 2
              implicitWidth: refreshTimeText.implicitWidth + Config.space.sm * 2
              radius: Config.shape.corner.xs
              visible: refreshIconHover.hovered
              z: 1000

              Text {
                id: refreshTimeText

                anchors.centerIn: parent
                color: Config.color.on_surface
                font.family: Config.fontFamily
                font.pixelSize: Config.type.labelSmall.size
                font.weight: Config.type.labelSmall.weight
                text: root.subtitle !== "" ? root.subtitle : "Refreshing..."
              }
            }
          }
          Item {
            Layout.fillWidth: true
            visible: root.title === "" && root.subtitle === ""
          }
          Item {
            Layout.preferredHeight: 0
            Layout.preferredWidth: 0
            visible: root.pinnable
          }
        }
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Config.color.outline
          opacity: 0.3
          visible: headerRow.visible
        }
        MK.Flickable {
          id: flickable

          property real loadedContentHeight: 0
          property real loadedContentWidth: 0

          function setContentYImmediate(value) {
            const maxY = Math.max(0, flickable.contentHeight - flickable.height)
            const nextY = Math.max(0, Math.min(value, maxY))
            flickable.suppressContentYBehavior = true
            flickable.contentY = nextY
            flickable.scrollTargetY = nextY
            flickable.suppressContentYBehavior = false
          }

          function resetContentOffset() {
            flickable.setContentYImmediate(0)
          }

          function clampContentOffset() {
            flickable.setContentYImmediate(flickable.contentY)
          }

          function updateContentSize() {
            if (contentLoader.status === Loader.Ready && contentLoader.item) {
              loadedContentHeight = contentLoader.item.implicitHeight
              loadedContentWidth = contentLoader.item.width
            } else {
              loadedContentHeight = 0
              loadedContentWidth = 0
            }
          }

          Layout.fillWidth: true
          Layout.preferredHeight: loadedContentHeight
          implicitWidth: loadedContentWidth
          contentHeight: loadedContentHeight
          contentWidth: loadedContentWidth
          showVerticalScrollBar: root.showScrollIndicator

          onHeightChanged: flickable.clampContentOffset()

          onContentHeightChanged: {
            if (contentHeight <= height) {
              flickable.resetContentOffset()
            } else if (root.autoScroll) {
              Qt.callLater(() => {
                flickable.setContentYImmediate(Math.max(0, flickable.contentHeight - flickable.height))
              })
            } else {
              flickable.clampContentOffset()
            }
          }

          Loader {
            id: contentLoader

            active: true
            opacity: 1
            sourceComponent: root.contentComponent

            Behavior on opacity {
              NumberAnimation {
                duration: Math.round(120 * Config.motionScale)
                easing.type: Easing.OutCubic
              }
            }

            onStatusChanged: {
              flickable.updateContentSize()
              if (status !== Loader.Loading)
                flickable.resetContentOffset()
            }
            onItemChanged: {
              contentLoader.opacity = 0
              Qt.callLater(() => {
                contentLoader.opacity = 1
              })
              flickable.resetContentOffset()
              flickable.updateContentSize()
              if (item) {
                item.implicitHeightChanged.connect(flickable.updateContentSize)
                item.widthChanged.connect(flickable.updateContentSize)
              }
            }
          }

          Rectangle {
            id: fadeOverlay

            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Config.space.lg
            visible: flickable.interactive && flickable.contentY < (flickable.contentHeight - flickable.height - 1)
            z: 1

            gradient: Gradient {
              GradientStop {
                color: "transparent"
                position: 0
              }
              GradientStop {
                color: Config.color.surface
                position: 1
              }
            }
          }
        }
      }
      HoverHandler {
        id: popupHover

        enabled: root.hoverable
        target: body
      }
    }
  }
}
