pragma ComponentBehavior: Bound
import ".."
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "../../common/components" as CommonComponents

Rectangle {
  id: root

  property color backgroundColor: Config.barModuleBackground
  readonly property bool backgroundTransparent: root.backgroundColor.a < 0.01
  property bool collapsed: false
  property alias content: contentRow.data
  readonly property int contentImplicitHeight: Math.max(contentRow.implicitHeight + root.paddingTop + root.paddingBottom, root.minHeight)
  readonly property int contentImplicitWidth: contentRow.implicitWidth + root.paddingLeft + root.paddingRight
  property int contentSpacing: Config.moduleSpacing
  readonly property bool hovered: hoverHandler.hovered
  property int marginBottom: Config.spaceHalfXs
  property int marginLeft: Config.moduleMarginX
  property int marginRight: Config.moduleMarginX
  property int marginTop: Config.outerGaps
  property int minHeight: Config.barHeight - Config.barPadding * 2
  property int paddingBottom: Config.modulePaddingY
  property int paddingLeft: Config.modulePaddingX
  property int paddingRight: Config.modulePaddingX
  property int paddingTop: Config.modulePaddingY
  readonly property color surfaceColor: root.backgroundTransparent ? "transparent" : root.backgroundColor
  readonly property bool tooltipActive: BarPopupState.activeFor(root)
  readonly property bool tooltipVisualActive: BarPopupState.visualActiveFor(root)
  // If provided as a string, it must be a URL (opened via xdg-open).
  // If provided as a list, it's treated as an argv array and executed detached.
  property var tooltipBrowserLink: ""
  property Component tooltipContent: null
  readonly property Component effectiveTooltipContent: root.tooltipContent ? root.tooltipContent : defaultTooltipContent
  readonly property bool tooltipEnabled: root.tooltipText !== "" || root.tooltipContent !== null
  property bool tooltipHoverable: true
  property bool tooltipPinned: false
  property bool tooltipRefreshing: false
  property bool tooltipShowBrowserIcon: false
  property bool tooltipShowRefreshIcon: false
  property string tooltipSubtitle: ""
  property string tooltipText: ""
  property string tooltipTitle: ""

  signal tooltipRefreshRequested
  signal clicked
  signal rightClicked

  function refreshSharedPopup() {
    BarPopupState.refreshFromTarget(root)
  }

  Layout.bottomMargin: root.marginBottom
  Layout.leftMargin: root.marginLeft
  Layout.rightMargin: root.marginRight
  Layout.topMargin: root.marginTop
  antialiasing: true
  color: root.surfaceColor
  border.width: root.backgroundTransparent ? 0 : Config.barModuleBorderWidth
  border.color: root.backgroundTransparent ? "transparent" : Config.color.outline_variant
  radius: Math.min(width, height) / 2
  implicitHeight: root.collapsed ? 0 : Math.round(root.contentImplicitHeight)
  implicitWidth: root.collapsed ? 0 : Math.round(root.contentImplicitWidth)
  visible: !root.collapsed
  layer.enabled: Config.barPillShadowsEnabled && !root.backgroundTransparent && root.visible
  layer.effect: MultiEffect {
    autoPaddingEnabled: true
    shadowEnabled: true
    shadowBlur: 0.25
    shadowColor: Qt.alpha(Config.color.shadow, 0.38)
    shadowHorizontalOffset: 0
    shadowVerticalOffset: 2
  }

  Behavior on color {
    ColorAnimation {
      duration: Config.motion.duration.shortMs
      easing.type: Config.motion.easing.standard
    }
  }
  RowLayout {
    id: contentRow

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: root.paddingLeft
    anchors.rightMargin: root.paddingRight
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: (root.paddingTop - root.paddingBottom) / 2
    height: implicitHeight
    spacing: root.contentSpacing
  }
  Rectangle {
    id: hoverOutline

    anchors.fill: parent
    anchors.margins: 0
    antialiasing: true
    border.color: Config.color.outline
    border.width: 0
    color: "transparent"
    radius: Math.min(width, height) / 2
    z: 1

    Behavior on border.color {
      ColorAnimation {
        duration: Config.motion.duration.medium
        easing.type: Config.motion.easing.standard
      }
    }
    Behavior on border.width {
      NumberAnimation {
        duration: Config.motion.duration.shortMs
        easing.type: Config.motion.easing.standard
      }
    }
  }
  HoverHandler {
    id: hoverHandler

    onHoveredChanged: {
      if (hovered)
        BarPopupState.requestTarget(root)
      else
        BarPopupState.releaseTarget(root)
    }
  }
  TapHandler {
    acceptedButtons: Qt.LeftButton
    gesturePolicy: TapHandler.ReleaseWithinBounds
    onTapped: root.clicked()
  }
  TapHandler {
    acceptedButtons: Qt.RightButton
    gesturePolicy: TapHandler.ReleaseWithinBounds
    onTapped: root.rightClicked()
  }
  Component {
    id: defaultTooltipContent

    CommonComponents.LinkText {
      color: Config.color.on_surface
      font.family: Config.fontFamily
      font.pixelSize: Config.type.bodyMedium.size
      font.weight: Config.type.bodyMedium.weight
      font.variableAxes: Config.fontVariableAxes(Config.type.bodyMedium.size, Config.type.bodyMedium.weight)
      text: root.tooltipText
      textFormat: Text.RichText
      wrapMode: Text.WordWrap
    }
  }

  Component.onCompleted: BarPopupState.registerTarget(root)
  Component.onDestruction: BarPopupState.unregisterTarget(root)

  onCollapsedChanged: if (root.collapsed) BarPopupState.releaseTarget(root)
  onTooltipBrowserLinkChanged: root.refreshSharedPopup()
  onTooltipContentChanged: root.refreshSharedPopup()
  onTooltipHoverableChanged: root.refreshSharedPopup()
  onTooltipRefreshingChanged: root.refreshSharedPopup()
  onTooltipShowBrowserIconChanged: root.refreshSharedPopup()
  onTooltipShowRefreshIconChanged: root.refreshSharedPopup()
  onTooltipSubtitleChanged: root.refreshSharedPopup()
  onTooltipTextChanged: root.refreshSharedPopup()
  onTooltipTitleChanged: root.refreshSharedPopup()
  onVisibleChanged: if (!root.visible) BarPopupState.releaseTarget(root)
}
