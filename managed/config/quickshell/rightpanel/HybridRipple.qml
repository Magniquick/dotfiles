import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property color color: "white"
    property int durationInMs: 420
    property int durationOutMs: 220
    property real pressX: width / 2
    property real pressY: height / 2
    property bool pressed: false
    property real radius: 0
    property bool stateLayerEnabled: true
    property color stateLayerColor: root.color
    property real stateOpacity: 0
    property bool waveEnabled: true

    readonly property real clampedRadius: Math.max(0, Math.min(Math.min(root.width, root.height) / 2, Number(root.radius) || 0))
    readonly property real clampedStateOpacity: Math.max(0, Math.min(1, Number(root.stateOpacity) || 0))
    readonly property real effectiveStateOpacity: root.stateLayerEnabled ? root.clampedStateOpacity : 0
    readonly property bool running: waveAnim.running || fadeAnim.running || waveShape.opacity > 0.001 || stateLayer.opacity > 0.001

    property real waveCenterX: width / 2
    property real waveCenterY: height / 2
    property real waveRadius: 0

    function startWave(x, y) {
        if (!root.waveEnabled || root.width <= 0 || root.height <= 0)
            return;

        root.waveCenterX = Math.max(0, Math.min(root.width, Number(x)));
        root.waveCenterY = Math.max(0, Math.min(root.height, Number(y)));
        root.waveRadius = Math.max(2, Math.min(root.width, root.height) * 0.04);
        waveShape.opacity = 0.2;
        waveAnim.restart();
    }

    function trigger(x, y) {
        root.startWave(x, y);
    }

    visible: root.running

    onPressedChanged: {
        if (root.pressed)
            root.startWave(root.pressX, root.pressY);
    }

    Rectangle {
        id: stateLayer

        anchors.fill: parent
        color: root.stateLayerColor
        opacity: root.effectiveStateOpacity
        radius: root.clampedRadius
        visible: opacity > 0.001
    }

    Shape {
        id: waveShape

        anchors.fill: parent
        opacity: 0
        visible: opacity > 0.001

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: root.color
            fillGradient: RadialGradient {
                centerX: root.waveCenterX
                centerY: root.waveCenterY
                centerRadius: root.waveRadius
                focalX: centerX
                focalY: centerY

                GradientStop {
                    position: 0
                    color: Qt.alpha(root.color, 1.0)
                }
                GradientStop {
                    position: 0.78
                    color: Qt.alpha(root.color, 1.0)
                }
                GradientStop {
                    position: 0.80
                    color: Qt.alpha(root.color, 0.0)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(root.color, 0.0)
                }
            }

            startX: root.clampedRadius
            startY: 0

            PathLine {
                x: root.width - root.clampedRadius
                y: 0
            }
            PathArc {
                relativeX: root.clampedRadius
                relativeY: root.clampedRadius
                radiusX: root.clampedRadius
                radiusY: root.clampedRadius
            }
            PathLine {
                x: root.width
                y: root.height - root.clampedRadius
            }
            PathArc {
                relativeX: -root.clampedRadius
                relativeY: root.clampedRadius
                radiusX: root.clampedRadius
                radiusY: root.clampedRadius
            }
            PathLine {
                x: root.clampedRadius
                y: root.height
            }
            PathArc {
                relativeX: -root.clampedRadius
                relativeY: -root.clampedRadius
                radiusX: root.clampedRadius
                radiusY: root.clampedRadius
            }
            PathLine {
                x: 0
                y: root.clampedRadius
            }
            PathArc {
                x: root.clampedRadius
                y: 0
                radiusX: root.clampedRadius
                radiusY: root.clampedRadius
            }
        }
    }

    NumberAnimation {
        id: waveAnim

        target: root
        property: "waveRadius"
        to: Math.sqrt(root.height * root.height + root.width * root.width) * 1.2
        duration: root.durationInMs
        easing.type: Easing.OutCubic

        onStopped: {
            if (waveShape.opacity > 0.001)
                fadeAnim.restart();
        }
    }

    NumberAnimation {
        id: fadeAnim

        target: waveShape
        property: "opacity"
        to: 0
        duration: root.durationOutMs
        easing.type: Easing.OutQuad
    }
}
