pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root

    property real borderRadius: 10
    // Shader customization properties
    property real dimOpacity: 0.6
    property url fragmentShader: Qt.resolvedUrl("../shaders/dimming.frag.qsb")
    property real lastMouseX: -1
    property real lastMouseY: -1
    property real outlineThickness: 2
    property int renderTick: 0
    property real selectionHeight: 0
    property var selectedTarget: null
    property real selectionWidth: 0
    property var windowTargets: []
    property real selectionX: 0
    property real selectionY: 0
    property url vertexShader: Qt.resolvedUrl("../shaders/dimming.vert.qsb")

    signal windowSelected(var target)

    function clearSelection() {
        root.selectedTarget = null;
        root.selectionX = 0;
        root.selectionY = 0;
        root.selectionWidth = 0;
        root.selectionHeight = 0;
    }

    function findTargetAt(mouseX, mouseY) {
        const targets = Array.isArray(root.windowTargets) ? root.windowTargets : [];
        let match = null;

        for (let index = 0; index < targets.length; index += 1) {
            const target = targets[index];
            if (!target)
                continue;

            const x = Number(target.x);
            const y = Number(target.y);
            const width = Number(target.width);
            const height = Number(target.height);
            if (mouseX >= x && mouseX <= x + width && mouseY >= y && mouseY <= y + height)
                match = target;
        }

        return match;
    }

    function refreshHover() {
        if (!root.visible || root.lastMouseX < 0 || root.lastMouseY < 0)
            return;

        const target = root.findTargetAt(root.lastMouseX, root.lastMouseY);
        if (!target) {
            root.clearSelection();
            return;
        }

        root.selectedTarget = target;
        root.selectionX = Number(target.x);
        root.selectionY = Number(target.y);
        root.selectionWidth = Number(target.width);
        root.selectionHeight = Number(target.height);
    }

    function resetSelection() {
        root.renderTick += 1;
        root.clearSelection();
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
    onWindowTargetsChanged: {
        root.resetSelection();
        if (root.visible)
            Qt.callLater(root.refreshHover);
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
    MouseArea {
        id: mouseArea

        anchors.fill: parent
        hoverEnabled: true
        z: 3

        onPositionChanged: mouse => {
            root.lastMouseX = mouse.x;
            root.lastMouseY = mouse.y;
            root.refreshHover();
        }
        onReleased: mouse => {
            const target = root.selectedTarget;
            if (!target)
                return;
            if (mouse.x < root.selectionX || mouse.x > root.selectionX + root.selectionWidth || mouse.y < root.selectionY || mouse.y > root.selectionY + root.selectionHeight)
                return;

            root.resetSelection();
            root.windowSelected(target);
        }
    }
}
