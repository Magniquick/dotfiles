import QtQuick
import QtQuick.Layouts

Rectangle {
    id: left

    property color borderColor
    property int borderRadius: 27
    property var colors: ColorPalette.palette
    property bool headpatting: false
    property int padBottom: 54
    property int padLeft: 47
    property int padRight: 74
    property int padTop: 27
    property real subtitleOffsetX: -59
    property real subtitleOffsetY: -10
    property int swatchBorder: 4
    property int swatchSize: 37

    border.color: Qt.rgba(borderColor.r, borderColor.g, borderColor.b, 0.4)
    border.width: 6
    bottomRightRadius: 0
    color: "transparent"
    implicitHeight: leftContent.implicitHeight + padTop + padBottom + border.width * 2
    implicitWidth: leftContent.implicitWidth + padLeft + padRight + border.width * 2
    radius: borderRadius
    topRightRadius: 0

    Column {
        id: leftContent

        anchors.bottom: parent.bottom
        anchors.bottomMargin: padBottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: padTop
        spacing: 26

        Column {
            spacing: 4

            Item {
                id: headlineWrap

                property real heartOffsetX: headline.paintedWidth - 7
                property real heartOffsetY: headline.paintedHeight * 0.38

                height: headline.paintedHeight
                implicitHeight: height
                implicitWidth: width
                width: headline.paintedWidth

                Text {
                    id: headline

                    color: colors.blue
                    font.family: "Battle Andy"
                    font.pointSize: 80
                    text: "Hello"
                }
                Text {
                    id: heart

                    color: colors.red
                    font.family: "JetBrainsMono NFP"
                    font.pointSize: 12
                    text: ""
                    x: headlineWrap.heartOffsetX
                    y: headlineWrap.heartOffsetY
                }
            }
            Item {
                id: subtitleWrap

                height: subtitle.paintedHeight
                implicitHeight: height
                implicitWidth: width
                width: subtitle.paintedWidth
                x: headlineWrap.width + subtitleOffsetX
                y: headlineWrap.height + subtitleOffsetY

                Text {
                    id: subtitle

                    color: colors.subtext0
                    font.family: "Kyok Medium"
                    font.pointSize: 17
                    text: "(again)"
                    x: -20
                    y: -30
                }
            }
        }
        Column {
            spacing: 6
            width: leftContent.width

            Text {
                color: colors.yellow
                font.italic: true
                font.pointSize: 27
                horizontalAlignment: Text.AlignHCenter
                renderType: Text.NativeRendering
                text: "❝"
                width: parent.width
            }
            Item {
                id: quoteSwap

                implicitHeight: Math.max(quoteBnuuy.implicitHeight, quoteBubbi.implicitHeight)
                width: parent.width

                Text {
                    id: quoteBnuuy

                    color: colors.text
                    font.family: "Kyok Medium"
                    font.italic: true
                    font.pointSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    opacity: headpatting ? 0 : 1
                    renderType: Text.NativeRendering
                    text: "“bnuuy art life”"
                    width: parent.width

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                        }
                    }
                }
                Text {
                    id: quoteBubbi

                    color: colors.text
                    font.family: "Kyok Medium"
                    font.italic: true
                    font.pointSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    opacity: headpatting ? 1 : 0
                    renderType: Text.NativeRendering
                    text: "“bubbi art life”"
                    width: parent.width

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                        }
                    }
                }
            }
            Item {
                id: authorSwap

                implicitHeight: Math.max(authorMarx.implicitHeight, authorMagni.implicitHeight)
                width: parent.width

                Text {
                    id: authorMarx

                    color: colors.subtext0
                    font.family: "Kyok Medium"
                    font.italic: true
                    font.pointSize: 14
                    horizontalAlignment: Text.AlignRight
                    opacity: headpatting ? 0 : 1
                    renderType: Text.NativeRendering
                    text: "–Karl Marx"
                    width: parent.width

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                        }
                    }
                }
                Text {
                    id: authorMagni

                    color: colors.subtext0
                    font.family: "Kyok Medium"
                    font.italic: true
                    font.pointSize: 14
                    horizontalAlignment: Text.AlignRight
                    opacity: headpatting ? 1 : 0
                    renderType: Text.NativeRendering
                    text: "–Magniquick"
                    width: parent.width

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                        }
                    }
                }
            }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: -12

            Repeater {
                model: [colors.red, colors.yellow, colors.green, colors.teal, colors.blue, colors.pink]

                delegate: Rectangle {
                    border.color: colors.base
                    border.width: swatchBorder
                    color: "transparent"
                    height: swatchSize
                    radius: 999
                    width: swatchSize

                    Rectangle {
                        anchors.centerIn: parent
                        color: modelData
                        height: swatchSize - swatchBorder * 2
                        radius: 999
                        width: swatchSize - swatchBorder * 2
                    }
                }
            }
        }
    }
}
