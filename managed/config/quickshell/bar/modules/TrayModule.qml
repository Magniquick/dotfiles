import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray

Item {
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

    implicitHeight: trayRow.implicitHeight
    implicitWidth: trayRow.implicitWidth

    RowLayout {
        id: trayRow

        spacing: Config.moduleSpacing

        Repeater {
            model: tray.items

            delegate: Item {
                id: trayItem

                function openTrayMenu() {
                    if (!root.parentWindow)
                        return;

                    const rect = root.parentWindow.itemRect(trayItem);
                    modelData.display(root.parentWindow, rect.x, rect.y + rect.height);
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
                    mipmap: true
                    smooth: true
                    source: root.iconSource(modelData.icon)
                    sourceSize.height: height
                    sourceSize.width: width
                    width: Config.iconSize + Config.space.xs
                }
                MouseArea {
                    id: toolTipArea

                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    anchors.fill: parent
                    hoverEnabled: true

                    onClicked: {
                        if (mouse.button === Qt.MiddleButton) {
                            modelData.secondaryActivate();
                            return;
                        }
                        if (mouse.button === Qt.LeftButton) {
                            if (modelData.onlyMenu)
                                trayItem.openTrayMenu();
                            else
                                modelData.activate();
                        }
                    }
                    onPressed: {
                        if (mouse.button === Qt.RightButton) {
                            trayItem.openTrayMenu();
                            mouse.accepted = true;
                        }
                    }
                    onWheel: {
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
            }
        }
    }
}
