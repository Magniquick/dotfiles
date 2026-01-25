import QtQuick

Item {
    id: root

    property real borderRadius: 10
    // Shader customization properties
    property real dimOpacity: 0.6
    property url fragmentShader: Qt.resolvedUrl("../shaders/dimming.frag.qsb")
    property real outlineThickness: 2
    property int renderTick: 0
    property real selectionHeight: 0
    property real selectionWidth: 0
    property real selectionX: 0
    property real selectionY: 0
    property point startPos
    property bool suppressAnimation: false
    property real targetHeight: 0
    property real targetWidth: 0
    property real targetX: 0
    property real targetY: 0
    property url vertexShader: Qt.resolvedUrl("../shaders/dimming.vert.qsb")
    property bool cancelPending: false
    readonly property bool selecting: mouseArea.pressed || targetWidth > 0 || targetHeight > 0 || selectionWidth > 0 || selectionHeight > 0

    signal regionSelected(real x, real y, real width, real height)

    function resetSelection() {
        root.suppressAnimation = true;
        root.renderTick += 1;
        root.startPos = Qt.point(0, 0);
        root.selectionX = 0;
        root.selectionY = 0;
        root.selectionWidth = 0;
        root.selectionHeight = 0;
        root.targetX = 0;
        root.targetY = 0;
        root.targetWidth = 0;
        root.targetHeight = 0;
        Qt.callLater(() => {
            return root.suppressAnimation = false;
        });
    }
    function cancelSelection() {
        cancelPending = !!(mouseArea && mouseArea.pressed);
        resetSelection();
    }

    Behavior on selectionHeight {
        enabled: !root.suppressAnimation

        SpringAnimation {
            damping: 0.4
            spring: 4
        }
    }
    Behavior on selectionWidth {
        enabled: !root.suppressAnimation

        SpringAnimation {
            damping: 0.4
            spring: 4
        }
    }
    Behavior on selectionX {
        enabled: !root.suppressAnimation

        SpringAnimation {
            damping: 0.4
            spring: 4
        }
    }
    Behavior on selectionY {
        enabled: !root.suppressAnimation

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
    MouseArea {
        id: mouseArea

        anchors.fill: parent
        z: 3

        onPositionChanged: mouse => {
            if (root.cancelPending)
                return;
            if (pressed) {
                const x = Math.min(root.startPos.x, mouse.x);
                const y = Math.min(root.startPos.y, mouse.y);
                const width = Math.abs(mouse.x - root.startPos.x);
                const height = Math.abs(mouse.y - root.startPos.y);
                root.targetX = x;
                root.targetY = y;
                root.targetWidth = width;
                root.targetHeight = height;
            }
        }
        onPressed: mouse => {
            root.cancelPending = false;
            root.startPos = Qt.point(mouse.x, mouse.y);
            root.targetX = mouse.x;
            root.targetY = mouse.y;
            root.targetWidth = 0;
            root.targetHeight = 0;
        }
        onReleased: {
            if (root.cancelPending) {
                root.cancelPending = false;
                return;
            }
            root.selectionX = root.targetX;
            root.selectionY = root.targetY;
            root.selectionWidth = root.targetWidth;
            root.selectionHeight = root.targetHeight;
            const regionX = Math.round(root.selectionX);
            const regionY = Math.round(root.selectionY);
            const regionWidth = Math.round(root.selectionWidth);
            const regionHeight = Math.round(root.selectionHeight);
            root.resetSelection();
            root.regionSelected(regionX, regionY, regionWidth, regionHeight);
        }

        Timer {
            id: updateTimer

            interval: 16
            repeat: true
            running: mouseArea.pressed && !root.cancelPending

            onTriggered: {
                root.selectionX = root.targetX;
                root.selectionY = root.targetY;
                root.selectionWidth = root.targetWidth;
                root.selectionHeight = root.targetHeight;
            }
        }
    }
}
