import QtQuick
import QtQuick.Layouts
import "../common" as Common

Item {
  id: root
  property real value: 0
  property color accent: Common.Config.primary
  property string label: ""
  property string subValue: ""

  implicitHeight: 120
  Layout.fillWidth: true

  Rectangle {
    anchors.fill: parent
    color: Common.Config.m3.surfaceContainerHigh
    radius: Common.Config.shape.corner.md
    border.width: 1
    border.color: Common.Config.m3.outline
    opacity: 0.9

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Common.Config.space.sm
      spacing: Common.Config.space.xs

      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        Canvas {
          id: gauge
          anchors.centerIn: parent
          width: Math.min(parent.width, parent.height) - 10
          height: width

          property real animatedValue: 0
          readonly property bool isVisible: root.QsWindow.window?.visible ?? false

          Behavior on animatedValue {
            enabled: gauge.isVisible
            NumberAnimation {
              duration: Common.Config.motion.duration.longMs
              easing.type: Easing.OutCubic
            }
          }

          onAnimatedValueChanged: requestPaint()

          Connections {
            target: root
            function onValueChanged() {
              if (gauge.isVisible) gauge.animatedValue = root.value
            }
          }

          Component.onCompleted: {
            if (gauge.isVisible) gauge.animatedValue = root.value
          }

          onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            const strokeWidth = 6;
            const center = width / 2;
            const radius = (width - strokeWidth) / 2;
            const startAngle = -Math.PI / 2;
            const endAngle = startAngle + (Math.PI * 2 * Math.min(Math.max(animatedValue, 0), 100) / 100);

            // Background track
            ctx.lineWidth = strokeWidth;
            ctx.strokeStyle = Common.Config.m3.surfaceVariant;
            ctx.lineCap = "round";
            ctx.beginPath();
            ctx.arc(center, center, radius, 0, Math.PI * 2);
            ctx.stroke();

            // Value arc
            ctx.strokeStyle = root.accent;
            ctx.beginPath();
            ctx.arc(center, center, radius, startAngle, endAngle);
            ctx.stroke();
          }
        }

        ColumnLayout {
          anchors.centerIn: parent
          spacing: -2
          Text {
            text: Math.round(root.value) + "%"
            color: Common.Config.m3.onSurface
            font { family: Common.Config.fontFamily; pixelSize: 14; weight: Font.Bold }
            Layout.alignment: Qt.AlignHCenter
          }
          Text {
            visible: root.subValue !== ""
            text: root.subValue
            color: Common.Config.textMuted
            font { family: Common.Config.fontFamily; pixelSize: 8; weight: Font.Medium }
            Layout.alignment: Qt.AlignHCenter
          }
        }
      }

      Text {
        Layout.fillWidth: true
        text: root.label
        color: Common.Config.textMuted
        font { family: Common.Config.fontFamily; pixelSize: 9; weight: Font.Black; letterSpacing: 1.2; capitalization: Font.AllUppercase }
        horizontalAlignment: Text.AlignHCenter
        opacity: 0.7
      }
    }
  }
}
