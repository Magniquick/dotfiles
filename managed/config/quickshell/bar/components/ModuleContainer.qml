import ".."
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property alias content: contentRow.data
    property int paddingLeft: Config.modulePaddingX
    property int paddingRight: Config.modulePaddingX
    property int paddingTop: Config.modulePaddingY
    property int paddingBottom: Config.modulePaddingY
    property int marginLeft: Config.moduleMarginX
    property int marginRight: Config.moduleMarginX
    property int marginTop: Config.moduleMarginTop
    property int marginBottom: Config.moduleMarginBottom
    property int contentSpacing: Config.moduleSpacing
    property color backgroundColor: Config.moduleBackground
    property string tooltipText: ""
    property string tooltipTitle: ""
    property string tooltipSubtitle: ""
    property Component tooltipContent: null
    property bool tooltipHoverable: true
    property bool tooltipShowRefreshIcon: false
    property bool tooltipShowBrowserIcon: false
    property string tooltipBrowserLink: ""
    property bool tooltipRefreshing: false
    property bool tooltipPinned: false
    readonly property bool tooltipEnabled: root.tooltipText !== "" || root.tooltipContent !== null
    readonly property bool tooltipActive: tooltipPopup.active
    readonly property bool hovered: hoverHandler.hovered
    readonly property bool backgroundTransparent: root.backgroundColor.a < 0.01
    readonly property color surfaceColor: root.backgroundTransparent ? "transparent" : root.backgroundColor
    property bool collapsed: false
    property int minHeight: Config.barHeight - Config.barPadding * 2
    readonly property int contentImplicitWidth: contentRow.implicitWidth + root.paddingLeft + root.paddingRight
    readonly property int contentImplicitHeight: Math.max(contentRow.implicitHeight + root.paddingTop + root.paddingBottom, root.minHeight)

    signal tooltipRefreshRequested

    color: root.surfaceColor
    radius: Math.min(width, height) / 2
    antialiasing: true
    implicitWidth: root.collapsed ? 0 : Math.round(root.contentImplicitWidth)
    implicitHeight: root.collapsed ? 0 : Math.round(root.contentImplicitHeight)
    visible: !root.collapsed
    Layout.leftMargin: root.marginLeft
    Layout.rightMargin: root.marginRight
    Layout.topMargin: root.marginTop
    Layout.bottomMargin: root.marginBottom

    RowLayout {
        id: contentRow

        anchors.fill: parent
        anchors.leftMargin: root.paddingLeft
        anchors.rightMargin: root.paddingRight
        anchors.topMargin: root.paddingTop
        anchors.bottomMargin: root.paddingBottom
        spacing: root.contentSpacing
    }

    Rectangle {
        id: hoverOutline

        anchors.fill: parent
        anchors.margins: 0
        color: "transparent"
        radius: Math.min(width, height) / 2
        border.width: 0
        border.color: Config.outline
        antialiasing: true
        z: 1

        Behavior on border.width {
            NumberAnimation {
                duration: Config.motion.duration.shortMs
                easing.type: Config.motion.easing.standard
            }
        }

        Behavior on border.color {
            ColorAnimation {
                duration: Config.motion.duration.medium
                easing.type: Config.motion.easing.standard
            }
        }
    }

    HoverHandler {
        id: hoverHandler
    }

    Component {
        id: defaultTooltipContent

        Text {
            text: root.tooltipText
            color: Config.textColor
            font.family: Config.fontFamily
            font.pixelSize: Config.type.bodyMedium.size
            font.weight: Config.type.bodyMedium.weight
            wrapMode: Text.WordWrap
            textFormat: Text.RichText
        }
    }

    TooltipPopup {
        id: tooltipPopup

        targetItem: root
        open: hoverHandler.hovered
        hoverable: root.tooltipHoverable
        enabled: root.tooltipEnabled
        pinned: root.tooltipPinned
        title: root.tooltipTitle
        subtitle: root.tooltipSubtitle
        showRefreshIcon: root.tooltipShowRefreshIcon || root.tooltipTitle === "Calendar"
        showBrowserIcon: root.tooltipShowBrowserIcon
        browserLink: root.tooltipBrowserLink
        refreshing: root.tooltipRefreshing
        onRefreshRequested: root.tooltipRefreshRequested()
        contentComponent: root.tooltipContent ? root.tooltipContent : defaultTooltipContent
    }

    Behavior on color {
        ColorAnimation {
            duration: Config.motion.duration.shortMs
            easing.type: Config.motion.easing.standard
        }
    }
}
