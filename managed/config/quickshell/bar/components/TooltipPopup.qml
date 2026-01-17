import ".."
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

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
    readonly property var window: targetItem ? targetItem.QsWindow.window : null

    signal refreshRequested

    function refreshAnchorRect() {
        if (!root.window || !root.targetItem)
            return;

        root.anchorRect = root.window.itemRect(root.targetItem);
    }
    function updateAnchor() {
        root.refreshAnchorRect();
        if (popup.visible)
            popup.anchor.updateAnchor();
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
                color: Config.tooltipBackground
                radius: Config.tooltipRadius
            }
            Rectangle {
                id: panelBorder

                antialiasing: true
                border.color: Config.tooltipBorder
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
                        color: Config.m3.primary
                        height: Config.space.sm
                        opacity: 0.9
                        radius: Config.shape.corner.xs
                        visible: true
                        width: Config.space.sm

                        SequentialAnimation on scale {
                            alwaysRunToEnd: false
                            loops: Animation.Infinite
                            running: pulse.visible && Config.tooltipPulseAnimationEnabled && popup.reveal > 0.01

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
                        color: Config.m3.onSurface
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

                            color: Config.m3.onSurfaceVariant
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

                                Quickshell.execDetached(["sh", "-c", root.browserLink.trim()]);
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

                            color: Config.m3.onSurfaceVariant
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
                            border.color: Config.m3.outline
                            border.width: 1
                            color: Config.m3.surfaceContainerHigh
                            implicitHeight: refreshTimeText.implicitHeight + Config.space.xs * 2
                            implicitWidth: refreshTimeText.implicitWidth + Config.space.sm * 2
                            radius: Config.shape.corner.xs
                            visible: refreshIconHover.hovered
                            z: 1000

                            Text {
                                id: refreshTimeText

                                anchors.centerIn: parent
                                color: Config.m3.onSurface
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
                    color: Config.m3.outline
                    opacity: 0.18
                    visible: headerRow.visible
                }
                Item {
                    implicitHeight: contentLoader.item ? contentLoader.item.implicitHeight : 0
                    implicitWidth: contentLoader.item ? contentLoader.item.width : 0

                    Flickable {
                        id: flickable

                        anchors.fill: parent
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        contentHeight: contentLoader.item ? contentLoader.item.implicitHeight : 0
                        contentWidth: contentLoader.item ? contentLoader.item.width : 0
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
                        }

                        ScrollIndicator.vertical: ScrollIndicator {
                            id: scrollIndicator

                            active: flickable.interactive
                            visible: root.showScrollIndicator && flickable.interactive

                            contentItem: Rectangle {
                                color: Config.m3.onSurfaceVariant
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
                    }

                    Rectangle {
                        id: fadeOverlay

                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: Config.space.lg
                        visible: flickable.interactive && flickable.contentY < (flickable.contentHeight - flickable.height - 1)

                        gradient: Gradient {
                            GradientStop {
                                color: "transparent"
                                position: 0
                            }
                            GradientStop {
                                color: Config.tooltipBackground
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
