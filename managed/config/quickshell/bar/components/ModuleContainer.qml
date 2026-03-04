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
    readonly property bool tooltipActive: tooltipPopup.active
    // If provided as a string, it must be a URL (opened via xdg-open).
    // If provided as a list, it's treated as an argv array and executed detached.
    property var tooltipBrowserLink: ""
    property Component tooltipContent: null
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
            text: root.tooltipText
            textFormat: Text.RichText
            wrapMode: Text.WordWrap
        }
    }
    TooltipPopup {
        id: tooltipPopup

        browserLink: root.tooltipBrowserLink
        contentComponent: root.tooltipContent ? root.tooltipContent : defaultTooltipContent
        enabled: root.tooltipEnabled
        hoverable: root.tooltipHoverable
        open: hoverHandler.hovered
        pinned: root.tooltipPinned
        refreshing: root.tooltipRefreshing
        showBrowserIcon: root.tooltipShowBrowserIcon
        showRefreshIcon: root.tooltipShowRefreshIcon || root.tooltipTitle === "Calendar"
        subtitle: root.tooltipSubtitle
        targetItem: root
        title: root.tooltipTitle

        onRefreshRequested: root.tooltipRefreshRequested()
    }
}
