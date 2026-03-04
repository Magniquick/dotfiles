import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

PanelWindow {
  id: root

  anchors {
    top: true
    right: true
  }

  margins {
    top: 28
    right: 28
  }

  implicitWidth: 460
  implicitHeight: 520
  color: "transparent"

  property real lValue: 0.72
  property real aValue: 0.06
  property real bValue: 0.14

  readonly property var conversion: oklabToSrgb(lValue, aValue, bValue)
  readonly property color previewColor: Qt.rgba(conversion.r, conversion.g, conversion.b, 1)
  readonly property string hexColor: rgbToHex(conversion.r, conversion.g, conversion.b)

  function clamp01(x) {
    return Math.max(0, Math.min(1, x));
  }

  function linearToSrgb(x) {
    const v = Math.max(0, x);
    if (v <= 0.0031308)
      return 12.92 * v;
    return 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
  }

  function oklabToSrgb(l, a, b) {
    const l_ = l + 0.3963377774 * a + 0.2158037573 * b;
    const m_ = l - 0.1055613458 * a - 0.0638541728 * b;
    const s_ = l - 0.0894841775 * a - 1.2914855480 * b;

    const l3 = l_ * l_ * l_;
    const m3 = m_ * m_ * m_;
    const s3 = s_ * s_ * s_;

    const rLin = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3;
    const gLin = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3;
    const bLin = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3;

    const r = linearToSrgb(rLin);
    const g = linearToSrgb(gLin);
    const bOut = linearToSrgb(bLin);

    const clipped = r < 0 || r > 1 || g < 0 || g > 1 || bOut < 0 || bOut > 1;

    return {
      r: clamp01(r),
      g: clamp01(g),
      b: clamp01(bOut),
      clipped: clipped,
      rLin: rLin,
      gLin: gLin,
      bLin: bLin
    };
  }

  function toHexByte(v) {
    const n = Math.round(clamp01(v) * 255);
    const s = n.toString(16).toUpperCase();
    return s.length < 2 ? "0" + s : s;
  }

  function rgbToHex(r, g, b) {
    return "#" + toHexByte(r) + toHexByte(g) + toHexByte(b);
  }

  function randomize() {
    lValue = Math.random();
    aValue = -0.4 + Math.random() * 0.8;
    bValue = -0.4 + Math.random() * 0.8;
  }

  Rectangle {
    anchors.fill: parent
    radius: 22
    color: "#0E1218"
    border.width: 1
    border.color: "#2A3440"
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 18
    spacing: 14

    RowLayout {
      Layout.fillWidth: true

      Text {
        text: "OKLAB Playground"
        color: "#E8EEF6"
        font.pixelSize: 18
        font.weight: Font.DemiBold
      }

      Item {
        Layout.fillWidth: true
      }

      Button {
        text: "Random"
        onClicked: root.randomize()
      }

      Button {
        text: "Reset"
        onClicked: {
          root.lValue = 0.72;
          root.aValue = 0.06;
          root.bValue = 0.14;
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 136
      radius: 14
      color: root.previewColor
      border.width: 1
      border.color: "#3A4654"

      Column {
        anchors {
          left: parent.left
          bottom: parent.bottom
          margins: 12
        }
        spacing: 2

        Text {
          text: root.hexColor
          color: "white"
          font.pixelSize: 20
          font.weight: Font.Bold
        }

        Text {
          text: root.conversion.clipped ? "Out of sRGB gamut (clipped)" : "Inside sRGB gamut"
          color: "white"
          opacity: 0.88
          font.pixelSize: 12
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.fillHeight: true
      radius: 14
      color: "#121922"
      border.width: 1
      border.color: "#26303B"

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        GridLayout {
          Layout.fillWidth: true
          columns: 3
          columnSpacing: 10
          rowSpacing: 8

          Text {
            text: "L"
            color: "#D7E0EA"
            font.pixelSize: 15
            font.weight: Font.DemiBold
          }

          Slider {
            Layout.fillWidth: true
            from: 0
            to: 1
            value: root.lValue
            onMoved: root.lValue = value
          }

          Text {
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 66
            text: root.lValue.toFixed(3)
            color: "#AFC0D3"
            font.pixelSize: 13
          }

          Text {
            text: "a"
            color: "#D7E0EA"
            font.pixelSize: 15
            font.weight: Font.DemiBold
          }

          Slider {
            Layout.fillWidth: true
            from: -0.4
            to: 0.4
            value: root.aValue
            onMoved: root.aValue = value
          }

          Text {
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 66
            text: root.aValue.toFixed(3)
            color: "#AFC0D3"
            font.pixelSize: 13
          }

          Text {
            text: "b"
            color: "#D7E0EA"
            font.pixelSize: 15
            font.weight: Font.DemiBold
          }

          Slider {
            Layout.fillWidth: true
            from: -0.4
            to: 0.4
            value: root.bValue
            onMoved: root.bValue = value
          }

          Text {
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 66
            text: root.bValue.toFixed(3)
            color: "#AFC0D3"
            font.pixelSize: 13
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: "#26303B"
        }

        Text {
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
          text: "Ranges: L [0..1], a [-0.4..0.4], b [-0.4..0.4]. We convert Oklab -> linear sRGB -> gamma sRGB and clamp to display."
          color: "#8EA0B2"
          font.pixelSize: 12
        }

        Text {
          Layout.fillWidth: true
          text: "Linear RGB:  r " + root.conversion.rLin.toFixed(4) + "   g " + root.conversion.gLin.toFixed(4) + "   b " + root.conversion.bLin.toFixed(4)
          color: "#8EA0B2"
          font.pixelSize: 12
          elide: Text.ElideRight
        }
      }
    }
  }
}
