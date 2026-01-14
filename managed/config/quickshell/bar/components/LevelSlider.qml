import ".."
import QtQuick

Item {
    id: root

    property int barHeight: Config.slider.barHeight
    readonly property real displayValue: (root.dragging && !isNaN(root.dragValue)) ? root.dragValue : root.value
    property real dragValue: NaN
    property bool dragging: false
    property color fillColor: Config.m3.primary
    property color knobColor: Config.m3.primary
    property int knobSize: Config.slider.knobSize
    property int knobWidth: Config.slider.knobWidth
    property real maximum: 1
    property real minimum: 0
    property int snapSteps: 0
    property color trackColor: Config.m3.surfaceVariant
    property real value: 0
    property bool hovered: false
    property real hoverRatio: 0  // 0-1 ratio of hover position along track

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

    implicitHeight: Math.max(root.barHeight, root.knobSize)
    implicitWidth: 180
    opacity: root.enabled ? 1 : 0.5

    Rectangle {
        id: track

        anchors.verticalCenter: parent.verticalCenter
        color: root.trackColor
        height: root.barHeight
        radius: root.barHeight / 2
        width: parent.width
    }
    Rectangle {
        id: fill

        anchors.verticalCenter: track.verticalCenter
        color: root.fillColor
        height: track.height
        radius: track.radius
        width: track.width * root.clampedRatio()
    }
    Rectangle {
        id: knob

        antialiasing: true
        color: root.knobColor
        height: root.knobSize
        radius: root.knobSize / 2
        width: root.knobWidth
        x: (track.width * root.clampedRatio()) - (root.knobWidth / 2)
        y: (height - root.knobSize) / 2
        opacity: 1

        Behavior on opacity {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutQuad
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        enabled: root.enabled
        hoverEnabled: true

        onPositionChanged: mouse => {
            root.hoverRatio = Math.max(0, Math.min(1, mouse.x / width));
            if (root.dragging)
                root.updateFromPosition(mouse.x);
        }
        onPressed: mouse => {
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
