/**
 * @module TrayModule
 * @description System tray icon display with menu support
 *
 * Features:
 * - Displays all system tray icons
 * - Left-click activates item
 * - Right-click opens context menu
 * - Handles various icon formats (png, svg, xpm, jpg)
 *
 * Dependencies:
 * - Quickshell.Services.SystemTray: Tray item provider
 */
pragma ComponentBehavior: Bound
import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell._Window
import Quickshell.Services.SystemTray

ModuleContainer {
    id: root

    readonly property var knownIconExtensions: ["png", "svg", "xpm", "jpg", "jpeg"]
    property var parentWindow
    readonly property var tray: SystemTray
    readonly property int trayItemCount: root.getTrayItemCount()

    function getTrayItemCount() {
        if (!root.tray || !root.tray.items)
            return 0;

        if (root.tray.items.length !== undefined)
            return root.tray.items.length;
        if (root.tray.items.count !== undefined)
            return root.tray.items.count;

        return 0;
    }

    function iconSource(iconName) {
        if (!iconName)
            return "";

        const pathIndex = iconName.indexOf("?path=");
        if (pathIndex < 0)
            return iconName;

        let base = iconName.slice(0, pathIndex);
        const path = iconName.slice(pathIndex + 6).replace(/\/+$/, "");
        if (!path)
            return base;

        const schemePrefix = "image://icon/";
        if (base.startsWith(schemePrefix))
            base = base.slice(schemePrefix.length);

        const hasExtension = root.knownIconExtensions.some(ext => {
            return base.toLowerCase().endsWith("." + ext);
        });
        if (hasExtension)
            return path + "/" + base;

        return path + "/" + base + ".png";
    }

    backgroundColor: Config.barModuleBackground
    collapsed: root.trayItemCount === 0
    contentSpacing: Config.moduleSpacing
    paddingLeft: Config.modulePaddingX
    paddingRight: Config.modulePaddingX
    paddingTop: Config.modulePaddingY
    paddingBottom: Config.modulePaddingY
    property var drawerGroup: null
    property bool drawerOpenOnHoverDefault: true

    function findDrawerGroup() {
        let p = root.parent;
        while (p) {
            if (p.hasOwnProperty && p.hasOwnProperty("open") && p.hasOwnProperty("openOnHover"))
                return p;
            p = p.parent;
        }
        return null;
    }
    function setDrawerSticky(enabled) {
        if (!root.drawerGroup)
            return;

        if (enabled) {
            root.drawerOpenOnHoverDefault = root.drawerGroup.openOnHover;
            root.drawerGroup.openOnHover = false;
            root.drawerGroup.open = true;
            return;
        }

        root.drawerGroup.openOnHover = root.drawerOpenOnHoverDefault;
    }

    Component.onCompleted: {
        root.drawerGroup = root.findDrawerGroup();
        if (root.drawerGroup)
            root.drawerOpenOnHoverDefault = root.drawerGroup.openOnHover;
    }

    content: [
        RowLayout {
            id: trayRow

            spacing: Config.moduleSpacing
            Layout.alignment: Qt.AlignVCenter
            Item {
                id: trayContainer

                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: trayContent.implicitHeight
                Layout.preferredWidth: trayContent.implicitWidth
                implicitHeight: trayContent.implicitHeight
                implicitWidth: trayContent.implicitWidth
                clip: true
                RowLayout {
                    id: trayContent

                    anchors.fill: parent
                    spacing: Config.moduleSpacing

                    Repeater {
                        model: root.tray.items

                        delegate: Item {
                            id: trayItem

                            required property var modelData
                            property rect menuAnchorRect: Qt.rect(0, 0, 0, 0)
                            property var menuWindow: root.parentWindow || trayItem.QsWindow.window

                            QsMenuOpener {
                                id: menuOpener

                                menu: trayItem.modelData.menu
                            }
                            HoverHandler {
                                id: trayHover
                            }
                            Timer {
                                id: menuCloseTimer

                                interval: 160
                                repeat: false

                                onTriggered: {
                                    if (!trayHover.hovered && !menuHover.hovered)
                                        menuPopup.visible = false;
                                }
                            }

                            function openTrayMenu() {
                                const window = trayItem.menuWindow;
                                if (!window)
                                    return;

                                const rect = window.itemRect(trayItem);
                                trayItem.menuAnchorRect = rect;
                                if (menuOpener.menu) {
                                    // qmllint disable unresolved-type
                                    menuPopup.anchor.window = window;
                                    menuPopup.anchor.rect.x = rect.x;
                                    menuPopup.anchor.rect.y = rect.y + rect.height + Config.tooltipOffset;
                                    // qmllint enable unresolved-type
                                    menuPopup.visible = true;
                                    return;
                                }

                                trayItem.modelData.display(window, rect.x, rect.y + rect.height + Config.tooltipOffset);
                            }

                            Layout.preferredHeight: implicitHeight
                            Layout.preferredWidth: implicitWidth
                            height: implicitHeight
                            implicitHeight: icon.height
                            implicitWidth: icon.width
                            width: implicitWidth

                            Image {
                                id: icon

                                fillMode: Image.PreserveAspectFit
                                height: Config.iconSize + Config.space.xs
                                source: root.iconSource(trayItem.modelData.icon)
                                sourceSize.height: Math.round(height * Config.devicePixelRatio)
                                sourceSize.width: Math.round(width * Config.devicePixelRatio)
                                width: Config.iconSize + Config.space.xs
                            }
                            MouseArea {
                                id: toolTipArea

                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: true
                                propagateComposedEvents: true

                                onClicked: function (mouse) {
                                    if (mouse.button === Qt.MiddleButton) {
                                        trayItem.modelData.secondaryActivate();
                                        return;
                                    }
                                    if (mouse.button === Qt.LeftButton) {
                                        const activateFn = trayItem.modelData.activate;
                                        if (trayItem.modelData.onlyMenu || !activateFn) {
                                            trayItem.openTrayMenu();
                                            return;
                                        }
                                        trayItem.modelData.activate();
                                    }
                                }
                                onPressed: function (mouse) {
                                    if (mouse.button === Qt.RightButton) {
                                        trayItem.openTrayMenu();
                                        mouse.accepted = true;
                                    }
                                }
                                onWheel: function (wheel) {
                                    trayItem.modelData.scroll(wheel.angleDelta.y, false);
                                }
                            }
                            TooltipPopup {
                                enabled: (trayItem.modelData.tooltipTitle || trayItem.modelData.tooltipDescription || "") !== ""
                                open: toolTipArea.containsMouse
                                targetItem: trayItem

                                contentComponent: Component {
                                    Text {
                                        color: Config.color.on_surface
                                        font.family: Config.fontFamily
                                        font.pixelSize: Config.fontSize
                                        text: trayItem.modelData.tooltipTitle || trayItem.modelData.tooltipDescription || ""
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                            PopupWindow {
                                id: menuPopup

                                readonly property real desiredWidth: menuLayout.implicitWidth + Config.tooltipPadding * 2 + Config.tooltipBorderWidth * 2
                                readonly property real desiredHeight: menuLayout.implicitHeight + Config.tooltipPadding * 2 + Config.tooltipBorderWidth * 2

                                color: "transparent"
                                visible: false
                                implicitWidth: desiredWidth
                                implicitHeight: desiredHeight

                                onVisibleChanged: {
                                    if (visible) {
                                        if (menuOpener.menu && menuOpener.menu.sendOpened)
                                            menuOpener.menu.sendOpened();
                                        menuCard.forceActiveFocus();
                                        root.setDrawerSticky(true);
                                    } else {
                                        if (menuOpener.menu && menuOpener.menu.sendClosed)
                                            menuOpener.menu.sendClosed();
                                        root.setDrawerSticky(false);
                                    }
                                }

                                anchor {
                                    rect.width: implicitWidth
                                    rect.height: implicitHeight
                                }
                                Rectangle {
                                    id: menuCard

                                    anchors.margins: Config.tooltipBorderWidth
                                    anchors.fill: parent
                                    antialiasing: true
                                    border.color: Config.color.outline
                                    border.width: Config.tooltipBorderWidth
                                    color: Config.color.surface_container
                                    focus: true
                                    radius: Config.tooltipRadius
                                    implicitHeight: menuPopup.desiredHeight - Config.tooltipBorderWidth * 2
                                    implicitWidth: menuPopup.desiredWidth - Config.tooltipBorderWidth * 2
                                    Keys.onEscapePressed: menuPopup.visible = false
                                    HoverHandler {
                                        id: menuHover
                                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                    }

                                    ColumnLayout {
                                        id: menuLayout

                                        anchors.fill: parent
                                        anchors.margins: Config.tooltipPadding
                                        spacing: Config.space.xs
                                        Repeater {
                                            model: menuOpener.menu ? menuOpener.children : []

                                            delegate: Item {
                                                id: menuEntry

                                                required property var modelData
                                                readonly property bool disabled: menuEntry.modelData.enabled === false
                                                readonly property bool isSeparator: menuEntry.modelData.isSeparator

                                                Layout.fillWidth: true
                                                implicitHeight: menuEntry.isSeparator ? (Config.space.xs + 1) : menuContent.implicitHeight
                                                implicitWidth: menuEntry.isSeparator ? 1 : (menuContent.implicitWidth + Config.space.sm * 2)
                                                Layout.preferredWidth: implicitWidth

                                                Rectangle {
                                                    anchors.fill: parent
                                                    color: menuMouseArea.containsMouse && !menuEntry.disabled ? Qt.alpha(Config.color.on_surface, Config.state.hoverOpacity) : "transparent"
                                                    radius: Config.shape.corner.xs
                                                    visible: !menuEntry.isSeparator
                                                }
                                                Rectangle {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    color: Config.color.outline
                                                    height: 1
                                                    opacity: 0.4
                                                    visible: menuEntry.isSeparator
                                                    width: parent.width
                                                }
                                                RowLayout {
                                                    id: menuContent

                                                    anchors.fill: parent
                                                    anchors.leftMargin: Config.space.sm
                                                    anchors.rightMargin: Config.space.sm
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: Config.space.sm
                                                    visible: !menuEntry.isSeparator
                                                    implicitHeight: Math.max(labelMetrics.height, Config.type.bodyMedium.size)
                                                    implicitWidth: labelMetrics.width + Config.space.sm * 2

                                                    Text {
                                                        color: menuEntry.disabled ? Config.color.on_surface_variant : Config.color.on_surface
                                                        font.family: Config.fontFamily
                                                        font.pixelSize: Config.type.bodyMedium.size
                                                        text: menuEntry.modelData.text
                                                        Layout.fillWidth: true
                                                        wrapMode: Text.NoWrap
                                                        elide: Text.ElideRight
                                                    }
                                                    TextMetrics {
                                                        id: labelMetrics

                                                        font.family: Config.fontFamily
                                                        font.pixelSize: Config.type.bodyMedium.size
                                                        text: menuEntry.modelData.text
                                                    }
                                                }
                                                MouseArea {
                                                    id: menuMouseArea

                                                    anchors.fill: parent
                                                    enabled: !menuEntry.isSeparator && !menuEntry.disabled
                                                    hoverEnabled: true

                                                    onClicked: {
                                                        if (menuEntry.modelData.hasChildren) {
                                                            menuEntry.modelData.display(trayItem.menuWindow, trayItem.menuAnchorRect.x + menuCard.width, trayItem.menuAnchorRect.y);
                                                            menuPopup.visible = false;
                                                            return;
                                                        }

                                                        if (menuEntry.modelData.sendTriggered) {
                                                            menuEntry.modelData.sendTriggered();
                                                        } else if (menuEntry.modelData.triggered) {
                                                            menuEntry.modelData.triggered();
                                                        }
                                                        menuPopup.visible = false;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                function maybeClose() {
                                    if (!menuPopup.visible)
                                        return;

                                    if (trayHover.hovered || menuHover.hovered) {
                                        menuCloseTimer.stop();
                                        return;
                                    }

                                    if (!menuCloseTimer.running)
                                        menuCloseTimer.start();
                                }
                                Connections {
                                    target: menuHover
                                    function onHoveredChanged() {
                                        menuPopup.maybeClose();
                                    }
                                }
                                Connections {
                                    target: trayHover
                                    function onHoveredChanged() {
                                        menuPopup.maybeClose();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    ]
}
