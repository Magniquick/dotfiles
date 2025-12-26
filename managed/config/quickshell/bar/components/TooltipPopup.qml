import ".."
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    property Item targetItem: null
    property Component contentComponent: null
    property bool open: false
    property bool hoverable: false
    property bool enabled: true
    property string title: ""
    property string subtitle: ""
    property bool showRefreshIcon: false
    property bool showBrowserIcon: false
    property string browserLink: ""
    property bool refreshing: false
    property bool pinnable: false
    property bool pinned: false
    readonly property var window: targetItem ? targetItem.QsWindow.window : null
    property rect anchorRect: Qt.rect(0, 0, 0, 0)
    readonly property bool popupHovered: popupHover.hovered
    readonly property bool active: root.enabled && (root.open || root.pinned || (root.hoverable && root.popupHovered))

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
    onEnabledChanged: {}

    Connections {
        function onXChanged() {
            root.updateAnchor();
        }

        function onYChanged() {
            root.updateAnchor();
        }

        function onWidthChanged() {
            root.updateAnchor();
        }

        function onHeightChanged() {
            root.updateAnchor();
        }

        target: root.targetItem
    }

    PopupWindow {
        id: popup

        property real reveal: root.active ? 1 : 0

        visible: root.window && reveal > 0.01
        color: "transparent"
        implicitWidth: body.implicitWidth
        implicitHeight: body.implicitHeight
        onImplicitWidthChanged: root.updateAnchor()
        onImplicitHeightChanged: root.updateAnchor()

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
                        color: Config.primary
                        opacity: 0.9
                        visible: true
                        Layout.alignment: Qt.AlignVCenter

                        SequentialAnimation on scale {
                            running: pulse.visible && Config.tooltipPulseAnimationEnabled && popup.reveal > 0.01
                            loops: Animation.Infinite

                            NumberAnimation {
                                to: 1.25
                                duration: Config.motion.duration.pulse
                                easing.type: Config.motion.easing.standard
                            }

                            NumberAnimation {
                                to: 1
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
                        elide: Text.ElideRight
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // Browser icon
                    Item {
                        visible: root.showBrowserIcon && root.browserLink !== ""
                        implicitWidth: browserIconText.implicitWidth
                        implicitHeight: browserIconText.implicitHeight
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            id: browserIconText

                            text: "󰖟"
                            color: Config.textMuted
                            font.family: Config.iconFontFamily
                            font.pixelSize: Config.type.labelSmall.size
                            opacity: browserIconHover.hovered ? 0.9 : 0.6
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
                        visible: root.showRefreshIcon
                        implicitWidth: refreshIconText.implicitWidth
                        implicitHeight: refreshIconText.implicitHeight
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            id: refreshIconText

                            text: "󰑐"
                            color: Config.textMuted
                            font.family: Config.iconFontFamily
                            font.pixelSize: Config.type.labelSmall.size
                            opacity: refreshIconHover.hovered ? 0.9 : 0.6
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
                            visible: refreshIconHover.hovered
                            color: Config.surfaceContainerHigh
                            border.color: Config.outline
                            border.width: 1
                            radius: Config.shape.corner.xs
                            anchors.right: parent.left
                            anchors.rightMargin: Config.space.xs
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: refreshTimeText.implicitWidth + Config.space.sm * 2
                            implicitHeight: refreshTimeText.implicitHeight + Config.space.xs * 2
                            z: 1000

                            Text {
                                id: refreshTimeText

                                anchors.centerIn: parent
                                text: root.subtitle !== "" ? root.subtitle : "Refreshing..."
                                color: Config.textColor
                                font.family: Config.fontFamily
                                font.pixelSize: Config.type.labelSmall.size
                                font.weight: Config.type.labelSmall.weight
                            }
                        }
                    }

                    Item {
                        visible: root.title === "" && root.subtitle === ""
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
                    color: Config.outline
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

        Behavior on reveal {
            NumberAnimation {
                duration: Config.motion.duration.medium
                easing.type: Config.motion.easing.emphasized
            }
        }
    }
}
