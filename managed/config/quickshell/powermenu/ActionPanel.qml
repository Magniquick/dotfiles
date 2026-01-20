import QtQuick

Rectangle {
    id: right

    property color borderColor: Qt.rgba(88 / 255, 91 / 255, 112 / 255, 0.5)
    property int borderRadius: 27
    property alias bunnyHeadpatting: bunny.headpatting
    property var colors: ColorPalette.palette
    property int headpatResetDelay: 200
    property string hoverAction: ""
    property bool hoverEnabled: true
    property int iconPadding: 6
    property int padBottom: 0
    property int padH: 47
    property int padTop: 0
    property bool reveal: false
    property string selection: ""
    property bool suppressNextHover: false

    signal actionInvoked(string actionName)
    signal hoverUpdated(string actionName)

    border.color: "transparent"
    border.width: 6
    color: colors.base
    implicitHeight: rightContent.implicitHeight + padTop + padBottom + border.width * 2
    implicitWidth: rightContent.implicitWidth + padH * 2 + border.width * 2
    radius: borderRadius

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
            ctx.strokeStyle = Qt.rgba(right.borderColor.r, right.borderColor.g, right.borderColor.b, 0.4);
            ctx.lineWidth = strokeWidth;
            ctx.setLineDash([dash, gap]);
            ctx.lineCap = "butt";
            const strokeSegment = drawFn => {
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

        anchors.bottomMargin: right.padBottom
        anchors.fill: parent
        anchors.leftMargin: right.padH
        anchors.rightMargin: right.padH
        anchors.topMargin: right.padTop

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
                hoverAction: right.hoverAction
                hoverEnabled: right.hoverEnabled
                iconPadding: right.iconPadding
                reveal: right.reveal
                selection: right.selection
                suppressNextHover: right.suppressNextHover

                onActivated: action => {
                    return right.actionInvoked(action);
                }
                onHovered: action => {
                    return right.hoverUpdated(action);
                }
                onUnhovered: () => {
                    return right.hoverUpdated("");
                }
            }
            FooterStatus {
                anchors.horizontalCenter: parent.horizontalCenter
                colors: right.colors
                hoverAction: right.hoverAction
                selection: right.selection
            }
        }
    }
}
