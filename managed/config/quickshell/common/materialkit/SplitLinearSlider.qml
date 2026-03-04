import QtQuick

Item {
  id: root

  property real value: 0.0
  property real thickness: 16
  property real cornerRadius: thickness / 2
  property color trackColor: "#666666"
  property color fillColor: "#888888"
  property color dividerColor: "#aaaaaa"
  property color endDotColor: "white"
  property real dividerWidth: 4
  property real gapMultiplier: 3.1
  readonly property real gapOnEachSide: dividerWidth * gapMultiplier
  readonly property real totalGap: gapOnEachSide * 2 + dividerWidth
  property real endDotSize: 5
  property real innerCornerRadius: Math.max(1, Math.min(cornerRadius, thickness * 0.25))
  property bool enabled: true
  property bool dragging: mouseArea.pressed
  property bool hovered: mouseArea.containsMouse
  property real hoverRatio: 0.0

  signal dragEnded(real value)

  implicitWidth: 260
  implicitHeight: thickness

  function setValue(v) {
    value = Math.max(0, Math.min(1, v));
  }

  readonly property real _clamped: Math.max(0, Math.min(1, value))
  readonly property real _centerX: _clamped * root.width
  readonly property real _dw: dividerWidth / 2
  readonly property real _halfSpanBase: _dw + gapOnEachSide
  readonly property real _availLeft: _centerX
  readonly property real _availRight: root.width - _centerX
  readonly property real _s: Math.min(1,
                                      Math.max(0, _availLeft / Math.max(1, _halfSpanBase)),
                                      Math.max(0, _availRight / Math.max(1, _halfSpanBase)))
  readonly property real _leftEdge: Math.max(0, _centerX - _s * _halfSpanBase)
  readonly property real _rightEdge: Math.min(root.width, _centerX + _s * _halfSpanBase)

  Item {
    x: 0
    anchors.verticalCenter: parent.verticalCenter
    width: root._leftEdge
    height: root.thickness

    Rectangle {
      x: root.cornerRadius
      width: Math.max(0, parent.width - root.cornerRadius)
      height: root.thickness
      radius: root.innerCornerRadius
      color: root.fillColor
      antialiasing: true
      visible: width > 0
    }

    Rectangle {
      width: Math.min(root.thickness, parent.width)
      height: root.thickness
      radius: root.cornerRadius
      color: root.fillColor
      antialiasing: true
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.InOutQuad } }
  }

  Item {
    x: root._rightEdge
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(0, root.width - root._rightEdge)
    height: root.thickness

    Rectangle {
      x: 0
      width: Math.max(0, parent.width - root.cornerRadius)
      height: root.thickness
      radius: root.innerCornerRadius
      color: root.trackColor
      antialiasing: true
      visible: width > 0
    }

    Rectangle {
      width: Math.min(root.thickness, parent.width)
      height: root.thickness
      radius: root.cornerRadius
      color: root.trackColor
      antialiasing: true
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }

    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.InOutQuad } }
    Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.InOutQuad } }
  }

  Rectangle {
    width: root.dividerWidth
    height: root.thickness * 2.5
    radius: width / 2
    color: root.dividerColor
    anchors.verticalCenter: parent.verticalCenter
    x: root._centerX - width / 2
    z: 10

    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.InOutQuad } }
  }

  Rectangle {
    width: root.endDotSize
    height: root.endDotSize
    radius: width / 2
    color: root.endDotColor
    anchors.verticalCenter: parent.verticalCenter
    x: Math.round(root.width - root.endDotSize - Math.max(2, root.endDotSize / 2))
    visible: (root._rightEdge < root.width - 0.0001)
    opacity: 0.9
    z: 11
  }

  MouseArea {
    id: mouseArea

    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    preventStealing: true
    cursorShape: Qt.PointingHandCursor

    onPressed: function(e) {
      var rel = e.x / Math.max(1, root.width);
      root.hoverRatio = Math.max(0, Math.min(1, rel));
      root.setValue(rel);
    }

    onPositionChanged: function(e) {
      var rel = e.x / Math.max(1, root.width);
      root.hoverRatio = Math.max(0, Math.min(1, rel));
      if (!pressed)
        return;
      root.setValue(rel);
    }

    onEntered: function(e) {
      var xPos = (e && e.x !== undefined) ? e.x : mouseX;
      var rel = xPos / Math.max(1, root.width);
      root.hoverRatio = Math.max(0, Math.min(1, rel));
    }

    onExited: root.hoverRatio = 0
    onReleased: root.dragEnded(root.value)
  }
}
