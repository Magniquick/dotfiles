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
import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray

ModuleContainer {
    id: root

    readonly property var knownIconExtensions: ["png", "svg", "xpm", "jpg", "jpeg"]
    property var parentWindow
    readonly property var tray: SystemTray

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

    backgroundColor: Config.moduleBackground
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
                Layout.preferredWidth: width
                clip: true
                height: trayContent.implicitHeight
                width: trayContent.implicitWidth
                RowLayout {
                    id: trayContent

                    anchors.fill: parent
                    spacing: Config.moduleSpacing

                    Repeater {
                        model: tray.items

                        delegate: Item {
                            id: trayItem

                            property rect menuAnchorRect: Qt.rect(0, 0, 0, 0)
                            property var menuWindow: root.parentWindow || trayItem.QsWindow.window

                            QsMenuOpener {
                                id: menuOpener

                                menu: modelData.menu
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
                                    menuPopup.anchor.window = window;
                                    menuPopup.anchor.rect.x = rect.x;
                                    menuPopup.anchor.rect.y = rect.y + rect.height + Config.tooltipOffset;
                                    menuPopup.visible = true;
                                    return;
                                }

                                modelData.display(window, rect.x, rect.y + rect.height + Config.tooltipOffset);
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
                                source: root.iconSource(modelData.icon)
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

                                onClicked: function(mouse) {
                                    if (mouse.button === Qt.MiddleButton) {
                                        modelData.secondaryActivate();
                                        return;
                                    }
                                    if (mouse.button === Qt.LeftButton) {
                                        const activateFn = modelData.activate;
                                        if (modelData.onlyMenu || !activateFn) {
                                            trayItem.openTrayMenu();
                                            return;
                                        }
                                        modelData.activate();
                                    }
                                }
                                onPressed: function(mouse) {
                                    if (mouse.button === Qt.RightButton) {
                                        trayItem.openTrayMenu();
                                        mouse.accepted = true;
                                    }
                                }
                                onWheel: function(wheel) {
                                    modelData.scroll(wheel.angleDelta.y, false);
                                }
                            }
                            TooltipPopup {
                                enabled: (modelData.tooltipTitle || modelData.tooltipDescription || "") !== ""
                                open: toolTipArea.containsMouse
                                targetItem: trayItem

                                contentComponent: Component {
                                    Text {
                                        color: Config.m3.onSurface
                                        font.family: Config.fontFamily
                                        font.pixelSize: Config.fontSize
                                        text: modelData.tooltipTitle || modelData.tooltipDescription || ""
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
                                width: implicitWidth
                                height: implicitHeight

                                onVisibleChanged: {
                                    if (visible) {
                                        menuCard.forceActiveFocus();
                                        root.setDrawerSticky(true);
                                    } else {
                                        root.setDrawerSticky(false);
                                    }
                                }

                                anchor {
                                    rect.width: implicitWidth
                                    rect.height: implicitHeight
                                }
                                Keys.onEscapePressed: menuPopup.visible = false

                                Rectangle {
                                    id: menuCard

                                    anchors.margins: Config.tooltipBorderWidth
                                    anchors.fill: parent
                                    antialiasing: true
                                    border.color: Config.m3.outline
                                    border.width: Config.tooltipBorderWidth
                                    color: Config.surfaceContainer
                                    focus: true
                                    radius: Config.tooltipRadius
                                    implicitHeight: menuPopup.desiredHeight - Config.tooltipBorderWidth * 2
                                    implicitWidth: menuPopup.desiredWidth - Config.tooltipBorderWidth * 2
                                    HoverHandler {
                                        id: menuHover
                                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                    }

                                    ColumnLayout {
                                        id: menuLayout

                                        anchors.fill: parent
                                        anchors.margins: Config.tooltipPadding
                                        spacing: Config.space.xs
                                        implicitWidth: Math.max(width, childrenRect.width)

                                        Repeater {
                                            model: menuOpener.menu ? menuOpener.children : []

                                            delegate: Item {
                                                id: menuEntry

                                                readonly property bool disabled: !modelData.enabled
                                                readonly property bool isSeparator: modelData.isSeparator

                                                Layout.fillWidth: true
                                                implicitHeight: menuEntry.isSeparator ? (Config.space.xs + 1) : menuContent.implicitHeight
                                                implicitWidth: menuEntry.isSeparator ? (menuLayout.implicitWidth || 0) : (menuContent.implicitWidth + Config.space.sm * 2)
                                                Layout.preferredWidth: implicitWidth

                                                Rectangle {
                                                    anchors.fill: parent
                                                    color: menuMouseArea.containsMouse && !menuEntry.disabled
                                                        ? Qt.alpha(Config.m3.onSurface, Config.state.hoverOpacity)
                                                        : "transparent"
                                                    radius: Config.shape.corner.xs
                                                    visible: !menuEntry.isSeparator
                                                }
                                                Rectangle {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    color: Config.m3.outline
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
                                                        color: menuEntry.disabled ? Config.m3.onSurfaceVariant : Config.m3.onSurface
                                                        font.family: Config.fontFamily
                                                        font.pixelSize: Config.type.bodyMedium.size
                                                        text: modelData.text
                                                        Layout.fillWidth: true
                                                        wrapMode: Text.NoWrap
                                                        elide: Text.ElideRight
                                                    }
                                                    TextMetrics {
                                                        id: labelMetrics

                                                        font.family: Config.fontFamily
                                                        font.pixelSize: Config.type.bodyMedium.size
                                                        text: modelData.text
                                                    }
                                                }
                                                MouseArea {
                                                    id: menuMouseArea

                                                    anchors.fill: parent
                                                    enabled: !menuEntry.isSeparator && !menuEntry.disabled
                                                    hoverEnabled: true

                                                    onClicked: {
                                                        if (modelData.hasChildren) {
                                                            modelData.display(trayItem.menuWindow, trayItem.menuAnchorRect.x + menuCard.width, trayItem.menuAnchorRect.y);
                                                            menuPopup.visible = false;
                                                            return;
                                                        }

                                                        if (modelData.sendTriggered)
                                                            modelData.sendTriggered();
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
                                    function onHoveredChanged() { menuPopup.maybeClose(); }
                                }
                                Connections {
                                    target: trayHover
                                    function onHoveredChanged() { menuPopup.maybeClose(); }
                                }
                            }
                        }
                    }
                }
            }
        }
    ]
}
