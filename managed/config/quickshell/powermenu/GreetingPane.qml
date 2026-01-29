pragma ComponentBehavior: Bound
import QtQuick

Rectangle {
    id: leftPane

    property color borderColor
    property int borderRadius: 27
    property var colors
    property bool headpatting: false
    property int padBottom: 54
    property int padLeft: 47
    property int padRight: 74
    property int padTop: 27
    property real subtitleOffsetX: -59
    property real subtitleOffsetY: -10
    property int swatchBorder: 4
    property int swatchSize: 37

    border.color: Qt.alpha(borderColor, 0.4)
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
        anchors.bottomMargin: leftPane.padBottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: leftPane.padTop
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

                    color: leftPane.colors.primary
                    font.family: "Battle Andy"
                    font.pointSize: 80
                    text: "Hello"
                }
                Text {
                    id: heart

                    color: leftPane.colors.error
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
                x: headlineWrap.width + leftPane.subtitleOffsetX
                y: headlineWrap.height + leftPane.subtitleOffsetY

                Text {
                    id: subtitle

                    color: leftPane.colors.on_surface_variant
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
                color: leftPane.colors.secondary
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

                    color: leftPane.colors.on_surface
                    font.family: "Kyok Medium"
                    font.italic: true
                    font.pointSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    opacity: leftPane.headpatting ? 0 : 1
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

                    color: leftPane.colors.on_surface
                    font.family: "Kyok Medium"
                    font.italic: true
                    font.pointSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    opacity: leftPane.headpatting ? 1 : 0
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

                    color: leftPane.colors.on_surface_variant
                    font.family: "Kyok Medium"
                    font.italic: true
                    font.pointSize: 14
                    horizontalAlignment: Text.AlignRight
                    opacity: leftPane.headpatting ? 0 : 1
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

                    color: leftPane.colors.on_surface_variant
                    font.family: "Kyok Medium"
                    font.italic: true
                    font.pointSize: 14
                    horizontalAlignment: Text.AlignRight
                    opacity: leftPane.headpatting ? 1 : 0
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
                model: [leftPane.colors.error, leftPane.colors.secondary, leftPane.colors.tertiary, leftPane.colors.tertiary, leftPane.colors.primary, leftPane.colors.secondary]

                delegate: Rectangle {
                    id: swatch
                    required property color modelData

                    border.color: leftPane.colors.surface
                    border.width: leftPane.swatchBorder
                    color: "transparent"
                    height: leftPane.swatchSize
                    radius: 999
                    width: leftPane.swatchSize

                    Rectangle {
                        anchors.centerIn: parent
                        color: swatch.modelData
                        height: leftPane.swatchSize - leftPane.swatchBorder * 2
                        radius: 999
                        width: leftPane.swatchSize - leftPane.swatchBorder * 2
                    }
                }
            }
        }
    }
}
