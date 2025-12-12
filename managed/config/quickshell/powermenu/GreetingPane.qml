import QtQuick
import QtQuick.Layouts

Rectangle {
  id: left
  property var colors: ColorPalette.palette
  property color borderColor
  property int borderRadius: 27
  property int padLeft: 47
  property int padRight: 74
  property int padTop: 27
  property int padBottom: 54
  property real subtitleOffsetX: -59
  property real subtitleOffsetY: -10
  property int swatchSize: 37
  property int swatchBorder: 4
  property bool headpatting: false

  radius: borderRadius
  color: "transparent"
  border.width: 6
  border.color: Qt.rgba(borderColor.r, borderColor.g, borderColor.b, 0.4)
  topRightRadius: 0
  bottomRightRadius: 0

  implicitWidth: leftContent.implicitWidth + padLeft + padRight + border.width * 2
  implicitHeight: leftContent.implicitHeight + padTop + padBottom + border.width * 2

  Column {
    id: leftContent
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: padTop
    anchors.bottom: parent.bottom
    anchors.bottomMargin: padBottom
    spacing: 26

    Column {
      spacing: 4

      Item {
        id: headlineWrap
        width: headline.paintedWidth
        height: headline.paintedHeight
        implicitWidth: width
        implicitHeight: height
        property real heartOffsetX: headline.paintedWidth - 7
        property real heartOffsetY: headline.paintedHeight * 0.38

        Text {
          id: headline
          text: "Hello"
          font.pointSize: 80
          font.family: "Battle Andy"
          color: colors.blue
        }
        Text {
          id: heart
          text: ""
          font.family: "JetBrainsMono NFP"
          font.pointSize: 12
          color: colors.red
          x: headlineWrap.heartOffsetX
          y: headlineWrap.heartOffsetY
        }
      }

      Item {
        id: subtitleWrap
        width: subtitle.paintedWidth
        height: subtitle.paintedHeight
        implicitWidth: width
        implicitHeight: height
        x: headlineWrap.width + subtitleOffsetX
        y: headlineWrap.height + subtitleOffsetY

        Text {
          id: subtitle
          text: "(again)"
          font.family: "Kyok Medium"
          font.pointSize: 17
          color: colors.subtext0
          x: -20
          y: -30
        }
      }
    }

    Column {
      spacing: 6
      width: leftContent.width
      Text {
        text: "❝"
        font.pointSize: 27
        font.italic: true
        color: colors.yellow
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        renderType: Text.NativeRendering
      }
      Item {
        id: quoteSwap
        width: parent.width
        implicitHeight: Math.max(quoteBnuuy.implicitHeight, quoteBubbi.implicitHeight)
        Text {
          id: quoteBnuuy
          text: "“bnuuy art life”"
          font.pointSize: 14
          font.italic: true
          font.family: "Kyok Medium"
          color: colors.text
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          renderType: Text.NativeRendering
          opacity: headpatting ? 0 : 1
          Behavior on opacity { NumberAnimation { duration: 200 } }
        }
        Text {
          id: quoteBubbi
          text: "“bubbi art life”"
          font.pointSize: 14
          font.italic: true
          font.family: "Kyok Medium"
          color: colors.text
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          renderType: Text.NativeRendering
          opacity: headpatting ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 200 } }
        }
      }
      Item {
        id: authorSwap
        width: parent.width
        implicitHeight: Math.max(authorMarx.implicitHeight, authorMagni.implicitHeight)
        Text {
          id: authorMarx
          text: "–Karl Marx"
          font.pointSize: 14
          font.italic: true
          font.family: "Kyok Medium"
          color: colors.subtext0
          horizontalAlignment: Text.AlignRight
          width: parent.width
          renderType: Text.NativeRendering
          opacity: headpatting ? 0 : 1
          Behavior on opacity { NumberAnimation { duration: 200 } }
        }
        Text {
          id: authorMagni
          text: "–Magniquick"
          font.pointSize: 14
          font.italic: true
          font.family: "Kyok Medium"
          color: colors.subtext0
          horizontalAlignment: Text.AlignRight
          width: parent.width
          renderType: Text.NativeRendering
          opacity: headpatting ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 200 } }
        }
      }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: -12
      Repeater {
        model: [colors.red, colors.yellow, colors.green, colors.teal, colors.blue, colors.pink]
        delegate: Rectangle {
          width: swatchSize
          height: swatchSize
          radius: 999
          border.width: swatchBorder
          border.color: colors.base
          color: "transparent"

          Rectangle {
            anchors.centerIn: parent
            width: swatchSize - swatchBorder * 2
            height: swatchSize - swatchBorder * 2
            radius: 999
            color: modelData
          }
        }
      }
    }
  }
}
