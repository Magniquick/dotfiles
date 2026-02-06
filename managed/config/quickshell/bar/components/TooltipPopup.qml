import ".."
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell._Window
import "../../common" as Common

Item {
    id: root

    readonly property bool active: root.enabled && (root.open || root.pinned || (root.hoverable && root.popupHovered))
    property rect anchorRect: Qt.rect(0, 0, 0, 0)
    property bool autoScroll: true
    property string browserLink: ""
    property Component contentComponent: null
    property bool enabled: true
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
    property string title: ""
    readonly property var contentItem: contentLoader.item
    readonly property var window: targetItem ? targetItem.QsWindow.window : null
    property bool _anchorUpdatePending: false

    signal refreshRequested

    function refreshAnchorRect() {
        if (!root.window || !root.targetItem)
            return;

        const nextRect = root.window.itemRect(root.targetItem);
        if (nextRect.x === root.anchorRect.x
            && nextRect.y === root.anchorRect.y
            && nextRect.width === root.anchorRect.width
            && nextRect.height === root.anchorRect.height)
            return;

        root.anchorRect = nextRect;
    }
    function _updateAnchorNow() {
        root.refreshAnchorRect();
        // qmllint disable unresolved-type
        if (popup.visible)
            popup.anchor.updateAnchor();
    // qmllint enable unresolved-type
    }
    function updateAnchor() {
        if (root._anchorUpdatePending)
            return;

        root._anchorUpdatePending = true;
        Qt.callLater(() => {
            root._anchorUpdatePending = false;
            root._updateAnchorNow();
        });
    }

    onOpenChanged: root.updateAnchor()
    onTargetItemChanged: root.updateAnchor()

    Connections {
        function onHeightChanged() {
            root.updateAnchor();
        }
        function onWidthChanged() {
            root.updateAnchor();
        }
        function onXChanged() {
            root.updateAnchor();
        }
        function onYChanged() {
            root.updateAnchor();
        }

        target: root.targetItem
    }
    PopupWindow {
        id: popup

        property real reveal: root.active ? 1 : 0

        color: "transparent"
        implicitHeight: body.implicitHeight
        implicitWidth: body.implicitWidth
        visible: root.window && reveal > 0.01

        Behavior on reveal {
            NumberAnimation {
                duration: Config.motion.duration.medium
                easing.type: Config.motion.easing.emphasized
            }
        }

        onImplicitHeightChanged: root.updateAnchor()
        onImplicitWidthChanged: root.updateAnchor()
        // qmllint disable missing-type
        // qmllint disable unresolved-type
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
        // qmllint enable unresolved-type
        // qmllint enable missing-type
        Item {
            id: body

            implicitHeight: {
                const naturalHeight = layout.implicitHeight + Config.tooltipPadding * 2;
                if (root.maximumHeight > 0) {
                    return Math.min(naturalHeight, root.maximumHeight);
                }
                return naturalHeight;
            }
            implicitWidth: layout.implicitWidth + Config.tooltipPadding * 2
            opacity: popup.reveal
            scale: 0.96 + (0.04 * popup.reveal)
            transformOrigin: Item.Top
            y: Config.motion.distance.medium * (1 - popup.reveal)

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
                border.color: Config.barPopupBorderColor
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
                    visible: root.title !== "" || root.pinnable

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
                        visible: root.showBrowserIcon && root.browserLink !== ""

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
                                if (!root.browserLink || root.browserLink.trim() === "")
                                    return;

                                Common.ProcessHelper.execDetached(root.browserLink.trim());
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
                Flickable {
                    id: flickable

                    property real loadedContentHeight: 0
                    property real loadedContentWidth: 0

                    // qmllint disable missing-property
                    function updateContentSize() {
                        if (contentLoader.status === Loader.Ready && contentLoader.item) {
                            loadedContentHeight = contentLoader.item.implicitHeight;
                            loadedContentWidth = contentLoader.item.width;
                        } else {
                            loadedContentHeight = 0;
                            loadedContentWidth = 0;
                        }
                    }
                    // qmllint enable missing-property

                    Layout.fillWidth: true
                    Layout.preferredHeight: loadedContentHeight
                    implicitWidth: loadedContentWidth
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    contentHeight: loadedContentHeight
                    contentWidth: loadedContentWidth
                    interactive: contentHeight > height

                    onContentHeightChanged: {
                        if (root.autoScroll && contentHeight > height) {
                            Qt.callLater(() => {
                                flickable.contentY = Math.max(0, contentHeight - height);
                            });
                        }
                    }

                    Loader {
                        id: contentLoader

                        active: true
                        sourceComponent: root.contentComponent

                        onStatusChanged: flickable.updateContentSize()
                        // qmllint disable missing-property
                        onItemChanged: {
                            flickable.updateContentSize();
                            if (item) {
                                item.implicitHeightChanged.connect(flickable.updateContentSize);
                                item.widthChanged.connect(flickable.updateContentSize);
                            }
                        }
                        // qmllint enable missing-property
                    }

                    ScrollIndicator.vertical: ScrollIndicator {
                        id: scrollIndicator

                        active: flickable.interactive
                        visible: root.showScrollIndicator && flickable.interactive

                        contentItem: Rectangle {
                            color: Config.color.on_surface_variant
                            implicitWidth: 3
                            opacity: scrollIndicator.active ? 0.6 : 0.3
                            radius: width / 2

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Config.motion.duration.shortMs
                                    easing.type: Config.motion.easing.standard
                                }
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
