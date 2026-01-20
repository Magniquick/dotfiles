import ".."
import QtQuick
import QtQuick.Effects

Item {
    id: root

    property int barHeight: Config.slider.barHeight
    readonly property real displayValue: (root.dragging && !isNaN(root.dragValue)) ? root.dragValue : root.value
    property real dragValue: NaN
    property bool dragging: false
    property color fillColor: Config.m3.primary
    property color knobColor: Config.m3.onSurface
    property int knobSize: Config.slider.knobSize
    property int knobWidth: Config.slider.knobWidth
    property real maximum: 1
    property real minimum: 0
    property int snapSteps: 0
    property color trackColor: Config.m3.surfaceVariant
    property real value: 0
    property bool hovered: false
    property real hoverRatio: 0  // 0-1 ratio of hover position along track
    readonly property bool interactionActive: root.enabled && (root.hovered || root.dragging)
    readonly property int idleTrackHeight: Math.max(2, Math.round(root.barHeight * 0.6))
    readonly property int activeTrackHeight: Math.max(root.barHeight, root.idleTrackHeight + 2)
    readonly property real trackScale: root.interactionActive ? 1 : (root.idleTrackHeight / root.activeTrackHeight)
    readonly property int handleHeightIdle: Math.max(Math.round(root.knobSize * 1.2), Math.round(root.activeTrackHeight * 3))
    readonly property int handleHeightPressed: Math.round(root.handleHeightIdle * 1.35)
    readonly property int handleWidthIdle: Math.max(5, Math.round(root.knobWidth * 0.35))
    readonly property int handleWidthPressed: Math.max(root.handleWidthIdle + 2, Math.round(root.knobWidth * 0.55))
    readonly property real handleScaleY: root.dragging ? 1 : (root.handleHeightIdle / root.handleHeightPressed)
    readonly property real handleScaleX: root.dragging ? 1 : (root.handleWidthIdle / root.handleWidthPressed)

    signal userChanged(real value)
    signal dragEnded(real value)  // Fires when drag completes with final value

    function clampedRatio() {
        if (root.maximum <= root.minimum)
            return 0;

        const ratio = (root.displayValue - root.minimum) / (root.maximum - root.minimum);
        return Math.max(0, Math.min(1, ratio));
    }
    function snappedValue(value) {
        if (root.snapSteps <= 1)
            return value;

        const stepSize = (root.maximum - root.minimum) / (root.snapSteps - 1);
        if (stepSize <= 0)
            return root.minimum;

        const snapped = Math.round((value - root.minimum) / stepSize) * stepSize + root.minimum;
        return Math.max(root.minimum, Math.min(root.maximum, snapped));
    }
    function updateFromPosition(xPos) {
        const next = snappedValue(valueFromPosition(xPos));
        root.dragValue = next;
        root.userChanged(next);
    }
    function valueFromPosition(xPos) {
        if (width <= 0)
            return root.minimum;

        const ratio = Math.max(0, Math.min(1, xPos / width));
        return root.minimum + ratio * (root.maximum - root.minimum);
    }

    implicitHeight: Math.max(root.activeTrackHeight, root.handleHeightPressed)
    implicitWidth: 180
    opacity: root.enabled ? 1 : 0.5

    Rectangle {
        id: track

        anchors.verticalCenter: parent.verticalCenter
        color: root.trackColor
        height: root.activeTrackHeight
        radius: height / 2
        width: parent.width
        transform: Scale {
            id: trackScale
            origin.x: track.width / 2
            origin.y: track.height / 2
            xScale: 1
            yScale: root.trackScale
            Behavior on yScale {
                NumberAnimation {
                    duration: Config.motion.duration.shortMs
                    easing.type: Easing.OutQuad
                }
            }
        }
    }
    Rectangle {
        id: fill

        anchors.verticalCenter: track.verticalCenter
        color: root.fillColor
        height: track.height
        radius: height / 2
        width: track.width * root.clampedRatio()
        transform: Scale {
            id: fillScale
            origin.x: fill.width / 2
            origin.y: fill.height / 2
            xScale: 1
            yScale: root.trackScale
            Behavior on yScale {
                NumberAnimation {
                    duration: Config.motion.duration.shortMs
                    easing.type: Easing.OutQuad
                }
            }
        }

        layer.enabled: root.enabled && root.dragging
        // qmllint disable unqualified
        layer.effect: MultiEffect {
            shadowBlur: 0.7
            shadowColor: Qt.alpha(root.fillColor, 0.55)
            shadowEnabled: true
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
        }
        // qmllint enable unqualified

        Behavior on width {
            enabled: !root.dragging
            NumberAnimation {
                duration: Config.motion.duration.shortMs
                easing.type: Easing.OutQuad
            }
        }
    }
    Rectangle {
        id: knob

        antialiasing: true
        color: root.knobColor
        height: root.handleHeightPressed
        radius: width / 2
        width: root.handleWidthPressed
        x: (track.width * root.clampedRatio()) - (width / 2)
        anchors.verticalCenter: track.verticalCenter
        transform: Scale {
            id: knobScale
            origin.x: knob.width / 2
            origin.y: knob.height / 2
            xScale: root.handleScaleX
            yScale: root.handleScaleY
            Behavior on xScale {
                NumberAnimation {
                    duration: Config.motion.duration.shortMs
                    easing.type: Easing.OutBack
                }
            }
            Behavior on yScale {
                NumberAnimation {
                    duration: Config.motion.duration.shortMs
                    easing.type: Easing.OutBack
                }
            }
        }

        layer.enabled: root.enabled && (root.dragging || root.hovered)
        // qmllint disable unqualified
        layer.effect: MultiEffect {
            shadowBlur: root.dragging ? 0.9 : 0.35
            shadowColor: root.dragging ? Qt.alpha(root.fillColor, 0.8) : Qt.alpha(Config.m3.shadow, 0.4)
            shadowEnabled: true
            shadowHorizontalOffset: 0
            shadowVerticalOffset: root.dragging ? 0 : 2

            Behavior on shadowBlur {
                NumberAnimation {
                    duration: Config.motion.duration.shortMs
                    easing.type: Easing.OutQuad
                }
            }
            Behavior on shadowVerticalOffset {
                NumberAnimation {
                    duration: Config.motion.duration.shortMs
                    easing.type: Easing.OutQuad
                }
            }
            Behavior on shadowColor {
                ColorAnimation {
                    duration: Config.motion.duration.shortMs
                }
            }
        }
        // qmllint enable unqualified
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        enabled: root.enabled
        hoverEnabled: true

        onPositionChanged: function (mouse) {
            root.hoverRatio = Math.max(0, Math.min(1, mouse.x / width));
            if (root.dragging)
                root.updateFromPosition(mouse.x);
        }
        onPressed: function (mouse) {
            root.dragging = true;
            root.updateFromPosition(mouse.x);
        }
        onReleased: {
            if (!isNaN(root.dragValue))
                root.dragEnded(root.dragValue);
            root.dragging = false;
            root.dragValue = NaN;
        }
        onEntered: root.hovered = true
        onExited: {
            root.hovered = false;
            root.hoverRatio = 0;
        }
    }
}
