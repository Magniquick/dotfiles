pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland

Item {
    id: root

    property real borderRadius: 10
    // Shader customization properties
    property real dimOpacity: 0.6
    property url fragmentShader: Qt.resolvedUrl("../shaders/dimming.frag.qsb")
    property var monitor: Hyprland.focusedMonitor
    property real outlineThickness: 2
    property int renderTick: 0
    property real selectionHeight: 0
    property real selectionWidth: 0
    property real selectionX: 0
    property real selectionY: 0
    property url vertexShader: Qt.resolvedUrl("../shaders/dimming.vert.qsb")
    property var windows: workspace && workspace.toplevels ? workspace.toplevels : []
    property var workspace: monitor && monitor.activeWorkspace ? monitor.activeWorkspace : null

    signal checkHover(real mouseX, real mouseY)
    signal regionSelected(real x, real y, real width, real height)

    function resetSelection() {
        root.renderTick += 1;
        root.selectionX = 0;
        root.selectionY = 0;
        root.selectionWidth = 0;
        root.selectionHeight = 0;
    }

    Behavior on selectionHeight {
        SpringAnimation {
            damping: 0.4
            spring: 4
        }
    }
    Behavior on selectionWidth {
        SpringAnimation {
            damping: 0.4
            spring: 4
        }
    }
    Behavior on selectionX {
        SpringAnimation {
            damping: 0.4
            spring: 4
        }
    }
    Behavior on selectionY {
        SpringAnimation {
            damping: 0.4
            spring: 4
        }
    }

    Component.onCompleted: resetSelection()
    onVisibleChanged: {
        if (visible)
            resetSelection();
    }

    // Shader overlay
    ShaderEffect {
        property real _tick: root.renderTick
        property real borderRadius: root.borderRadius
        property real dimOpacity: root.dimOpacity
        property real outlineThickness: root.outlineThickness
        property vector2d screenSize: Qt.vector2d(root.width, root.height)
        property vector4d selectionRect: Qt.vector4d(root.selectionX, root.selectionY, root.selectionWidth, root.selectionHeight)

        anchors.fill: parent
        fragmentShader: root.fragmentShader
        vertexShader: root.vertexShader
        z: 0
    }
    Repeater {
        model: root.windows

        Item {
            id: windowItem

            required property var modelData

            Connections {
                function onCheckHover(mouseX, mouseY) {
                    const monitorX = root.monitor.lastIpcObject.x;
                    const monitorY = root.monitor.lastIpcObject.y;
                    const windowX = windowItem.modelData.lastIpcObject.at[0] - monitorX;
                    const windowY = windowItem.modelData.lastIpcObject.at[1] - monitorY;
                    const width = windowItem.modelData.lastIpcObject.size[0];
                    const height = windowItem.modelData.lastIpcObject.size[1];
                    if (mouseX >= windowX && mouseX <= windowX + width && mouseY >= windowY && mouseY <= windowY + height) {
                        root.selectionX = windowX;
                        root.selectionY = windowY;
                        root.selectionWidth = width;
                        root.selectionHeight = height;
                    }
                }

                target: root
            }
        }
    }
    MouseArea {
        id: mouseArea

        anchors.fill: parent
        hoverEnabled: true
        z: 3

        onPositionChanged: mouse => {
            root.checkHover(mouse.x, mouse.y);
        }
        onReleased: mouse => {
            if (mouse.x >= root.selectionX && mouse.x <= root.selectionX + root.selectionWidth && mouse.y >= root.selectionY && mouse.y <= root.selectionY + root.selectionHeight) {
                const regionX = Math.round(root.selectionX);
                const regionY = Math.round(root.selectionY);
                const regionWidth = Math.round(root.selectionWidth);
                const regionHeight = Math.round(root.selectionHeight);
                root.resetSelection();
                root.regionSelected(regionX, regionY, regionWidth, regionHeight);
            }
        }
    }
}
