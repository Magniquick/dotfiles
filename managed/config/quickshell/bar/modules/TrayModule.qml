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
import Qcm.Material as MD

ModuleContainer {
    id: root

    readonly property var knownIconExtensions: ["png", "svg", "xpm", "jpg", "jpeg"]
    property var parentWindow
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

    backgroundColor: "transparent"
    collapsed: SystemTray.items.count === 0
    contentSpacing: Config.moduleSpacing
    paddingLeft: Config.modulePaddingX
    paddingRight: Config.modulePaddingX
    paddingTop: Config.modulePaddingY
    paddingBottom: Config.modulePaddingY
    property var drawerGroup: null
    property bool drawerOpenOnHoverDefault: true
    property int drawerStickyHolds: 0

    function findDrawerGroup() {
        let p = root.parent;
        while (p) {
            if (p.hasOwnProperty && p.hasOwnProperty("open") && p.hasOwnProperty("openOnHover"))
                return p;
            p = p.parent;
        }
        return null;
    }
    function updateDrawerSticky() {
        if (!root.drawerGroup)
            return;

        if (root.drawerStickyHolds > 0) {
            root.drawerGroup.openOnHover = false;
            root.drawerGroup.open = true;
            return;
        }

        root.drawerGroup.openOnHover = root.drawerOpenOnHoverDefault;
        if (root.drawerGroup.openOnHover)
            root.drawerGroup.open = !!root.drawerGroup.hovered;
    }
    function setDrawerSticky(enabled) {
        if (!root.drawerGroup)
            return;

        if (enabled) {
            if (root.drawerStickyHolds === 0)
                root.drawerOpenOnHoverDefault = root.drawerGroup.openOnHover;
            root.drawerStickyHolds += 1;
        } else if (root.drawerStickyHolds > 0) {
            root.drawerStickyHolds -= 1;
        }

        root.updateDrawerSticky();
    }

    Component.onCompleted: {
        root.drawerGroup = root.findDrawerGroup();
        if (root.drawerGroup) {
            root.drawerOpenOnHoverDefault = root.drawerGroup.openOnHover;
            root.updateDrawerSticky();
        }
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
                        model: SystemTray.items

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
                                onHoveredChanged: {
                                    if (hovered && menuOpener.menu && (!root.drawerGroup || root.drawerGroup.reveal >= 1))
                                        trayItem.openTrayMenu();
                                }
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
                                // `sourceSize` is in physical pixels; use the DPR of the window this delegate
                                // is actually rendered in (fixes mixed-DPI setups).
                                sourceSize.height: Math.round(height * ((trayItem.QsWindow.window && trayItem.QsWindow.window.devicePixelRatio) ? trayItem.QsWindow.window.devicePixelRatio : 1))
                                sourceSize.width: Math.round(width * ((trayItem.QsWindow.window && trayItem.QsWindow.window.devicePixelRatio) ? trayItem.QsWindow.window.devicePixelRatio : 1))
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
                                enabled: !menuPopup.visible && (trayItem.modelData.tooltipTitle || trayItem.modelData.tooltipDescription || "") !== ""
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

                                readonly property real desiredWidth: menuLayout.implicitWidth + Config.tooltipPadding * 2 + Config.barModuleBorderWidth * 2
                                readonly property real desiredHeight: menuLayout.implicitHeight + Config.tooltipPadding * 2 + Config.barModuleBorderWidth * 2

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
                                Component.onDestruction: {
                                    if (menuPopup.visible)
                                        root.setDrawerSticky(false);
                                }

                                anchor {
                                    rect.width: implicitWidth
                                    rect.height: implicitHeight
                                }
                                Rectangle {
                                    id: menuCard

                                    anchors.margins: Config.barModuleBorderWidth
                                    anchors.fill: parent
                                    antialiasing: true
                                    border.color: Config.barModuleBorderColor
                                    border.width: Config.barModuleBorderWidth
                                    color: Config.barModuleBackground
                                    focus: true
                                    radius: Config.tooltipRadius
                                    implicitHeight: menuPopup.desiredHeight - Config.barModuleBorderWidth * 2
                                    implicitWidth: menuPopup.desiredWidth - Config.barModuleBorderWidth * 2
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

                                                HybridRipple {
                                                    anchors.fill: parent
                                                    color: Config.color.on_surface
                                                    pressX: menuMouseArea.pressX
                                                    pressY: menuMouseArea.pressY
                                                    pressed: menuMouseArea.pressed
                                                    radius: Config.shape.corner.xs
                                                    stateOpacity: menuMouseArea.containsMouse && !menuEntry.disabled ? Config.state.hoverOpacity : 0
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

                                                    property real pressX: width / 2
                                                    property real pressY: height / 2

                                                    anchors.fill: parent
                                                    enabled: !menuEntry.isSeparator && !menuEntry.disabled
                                                    hoverEnabled: true

                                                    onClicked: {
                                                        if (menuEntry.modelData.hasChildren) {
                                                            menuEntry.modelData.display(trayItem.menuWindow, trayItem.menuAnchorRect.x + menuCard.width, trayItem.menuAnchorRect.y);
                                                            menuPopup.visible = false;
                                                            return;
                                                        }

                                                        const entry = menuEntry.modelData;
                                                        menuPopup.visible = false;
                                                        Qt.callLater(() => entry.triggered());
                                                    }
                                                    onPressed: function(mouse) {
                                                        pressX = mouse.x;
                                                        pressY = mouse.y;
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
