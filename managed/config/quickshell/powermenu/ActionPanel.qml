import QtQuick
import QtQuick.Layouts


Rectangle {
  id: right
  property var colors: Palette.palette
  property color borderColor: Qt.rgba(0x58 / 255, 0x5B / 255, 0x70 / 255, 0.5)
  property int borderRadius: 27
  property int padH: 47
  property int padTop: 0
  property int padBottom: 0
  property int iconPadding: 6
  property int headpatResetDelay: 200
  property string selection: ""
  property string hoverAction: ""
  property bool reveal: false
  property bool hoverEnabled: true
  property bool suppressNextHover: false
  property alias bunnyHeadpatting: bunny.headpatting

  signal actionInvoked(string actionName)
  signal hoverUpdated(string actionName)

  radius: borderRadius
  color: colors.base
  border.width: 6
  border.color: "transparent"

  implicitWidth: rightContent.implicitWidth + padH * 2 + border.width * 2
  implicitHeight: rightContent.implicitHeight + padTop + padBottom + border.width * 2

  Canvas {
    id: dashBorder
    anchors.fill: parent
    anchors.margins: 0
    antialiasing: true
    onPaint: {
      const ctx = getContext("2d");
      const strokeWidth = right.border.width;
      const halfStroke = strokeWidth / 2;
      const radius = Math.max(0, right.radius - halfStroke);
      const left = halfStroke;
      const rightEdge = width - halfStroke;
      const top = halfStroke;
      const bottom = height - halfStroke;
      const dash = strokeWidth * 0.4;
      const gap = strokeWidth * 0.2;

      ctx.clearRect(0, 0, width, height);
      ctx.strokeStyle = Qt.rgba(borderColor.r, borderColor.g, borderColor.b, 0.4);
      ctx.lineWidth = strokeWidth;
      ctx.setLineDash([dash, gap]);
      ctx.lineCap = "butt";

      const strokeSegment = (drawFn) => {
        ctx.beginPath();
        drawFn();
        ctx.stroke();
      };

      strokeSegment(() => {
        ctx.moveTo(left + radius, top);
        ctx.lineTo(rightEdge - radius, top);
        ctx.quadraticCurveTo(rightEdge, top, rightEdge, top + radius);
      });

      strokeSegment(() => {
        ctx.moveTo(rightEdge, top + radius);
        ctx.lineTo(rightEdge, bottom - radius);
        ctx.quadraticCurveTo(rightEdge, bottom, rightEdge - radius, bottom);
      });

      strokeSegment(() => {
        ctx.moveTo(rightEdge - radius, bottom);
        ctx.lineTo(left + radius, bottom);
        ctx.quadraticCurveTo(left, bottom, left, bottom - radius);
      });

      strokeSegment(() => {
        ctx.moveTo(left, bottom - radius);
        ctx.lineTo(left, top + radius);
        ctx.quadraticCurveTo(left, top, left + radius, top);
      });
    }
  }

  Item {
    id: rightContentArea
    anchors.fill: parent
    anchors.leftMargin: padH
    anchors.rightMargin: padH
    anchors.topMargin: padTop
    anchors.bottomMargin: padBottom

    Column {
      id: rightContent
      anchors.centerIn: parent
      anchors.verticalCenterOffset: 12
      spacing: 30

      BunnyBlock {
        id: bunny
        anchors.horizontalCenter: parent.horizontalCenter
        colors: right.colors
        headpatResetDelay: right.headpatResetDelay
      }

      ActionGrid {
        anchors.horizontalCenter: parent.horizontalCenter
        colors: right.colors
        selection: right.selection
        iconPadding: right.iconPadding
        hoverAction: right.hoverAction
        hoverEnabled: right.hoverEnabled
        suppressNextHover: right.suppressNextHover
        reveal: right.reveal
        onHovered: (action) => right.hoverUpdated(action)
        onUnhovered: () => right.hoverUpdated("")
        onActivated: (action) => right.actionInvoked(action)
      }

      FooterStatus {
        anchors.horizontalCenter: parent.horizontalCenter
        colors: right.colors
        selection: right.selection
        hoverAction: right.hoverAction
      }
    }
  }
}
