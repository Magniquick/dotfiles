pragma ComponentBehavior: Bound
import ".."
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property color backgroundColor: Config.moduleBackground
    readonly property bool backgroundTransparent: root.backgroundColor.a < 0.01
    property bool collapsed: false
    property alias content: contentRow.data
    readonly property int contentImplicitHeight: Math.max(contentRow.implicitHeight + root.paddingTop + root.paddingBottom, root.minHeight)
    readonly property int contentImplicitWidth: contentRow.implicitWidth + root.paddingLeft + root.paddingRight
    property int contentSpacing: Config.moduleSpacing
    readonly property bool hovered: hoverHandler.hovered
    property int marginBottom: 0
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
    property string tooltipBrowserLink: ""
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

    Layout.bottomMargin: root.marginBottom
    Layout.leftMargin: root.marginLeft
    Layout.rightMargin: root.marginRight
    Layout.topMargin: root.marginTop
    antialiasing: true
    color: root.surfaceColor
    implicitHeight: root.collapsed ? 0 : Math.round(root.contentImplicitHeight)
    implicitWidth: root.collapsed ? 0 : Math.round(root.contentImplicitWidth)
    radius: Math.min(width, height) / 2
    visible: !root.collapsed

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
        border.color: Config.m3.outline
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
        onTapped: root.clicked()
    }
    Component {
        id: defaultTooltipContent

        Text {
            color: Config.m3.onSurface
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
