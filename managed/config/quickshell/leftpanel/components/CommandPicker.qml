pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../common" as Common

Rectangle {
    id: root

    property string command: ""
    property var options: []

    signal optionSelected(string value)
    signal dismissed

    color: Common.Config.m3.surfaceDim
    radius: Common.Config.shape.corner.xl
    border.width: 2
    border.color: Common.Config.primary

    width: 320
    height: Math.min(500, headerRow.height + optionsList.contentHeight + Common.Config.space.lg * 3 + Common.Config.space.md)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Common.Config.space.lg
        spacing: Common.Config.space.md

        // Header
        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            spacing: Common.Config.space.sm

            Text {
                text: "\uf120" // nf-md-console
                color: Common.Config.primary
                font.family: Common.Config.iconFontFamily
                font.pixelSize: 18
            }

            Text {
                text: root.command.toUpperCase()
                color: Common.Config.primary
                font.family: Common.Config.fontFamily
                font.pixelSize: 12
                font.weight: Font.Black
                font.letterSpacing: 2
            }

            Item {
                Layout.fillWidth: true
            }

            Rectangle {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                implicitWidth: 24
                implicitHeight: 24
                radius: 12
                color: closeArea.containsMouse ? Qt.alpha(Common.Config.m3.error, 0.2) : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "\uf00d" // nf-md-close
                    color: closeArea.containsMouse ? Common.Config.m3.error : Common.Config.textMuted
                    font.family: Common.Config.iconFontFamily
                    font.pixelSize: 14
                }

                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dismissed()
                }
            }
        }

        // Options list
        ListView {
            id: optionsList
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Common.Config.space.xs
            clip: true
            model: root.options

            delegate: Rectangle {
                id: optionItem
                required property int index
                required property var modelData

                readonly property color itemAccent: optionItem.modelData.accent || Common.Config.primary

                width: optionsList.width
                height: 56
                radius: Common.Config.shape.corner.md
                color: optionArea.containsMouse ? optionItem.itemAccent : Common.Config.surface
                border.width: 1
                border.color: optionArea.containsMouse ? optionItem.itemAccent : Qt.alpha(optionItem.itemAccent, 0.3)

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
                Behavior on border.color {
                    ColorAnimation {
                        duration: 150
                    }
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: Common.Config.space.md
                    spacing: Common.Config.space.md

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        sourceSize: Qt.size(36, 36)
                        source: optionItem.modelData.iconImage ? Qt.resolvedUrl("../" + optionItem.modelData.iconImage) : ""
                        visible: !!optionItem.modelData.iconImage
                        fillMode: Image.PreserveAspectFit
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: optionItem.modelData.icon || "\uf101"
                        color: optionArea.containsMouse ? Common.Config.onPrimary : optionItem.itemAccent
                        font.family: Common.Config.iconFontFamily
                        font.pixelSize: 18
                        visible: !optionItem.modelData.iconImage

                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: optionItem.modelData.label || ""
                            color: optionArea.containsMouse ? Common.Config.onPrimary : optionItem.itemAccent
                            font.family: Common.Config.fontFamily
                            font.pixelSize: Common.Config.type.bodyMedium.size
                            font.weight: Font.Medium

                            Behavior on color {
                                ColorAnimation {
                                    duration: 150
                                }
                            }
                        }

                        Text {
                            text: optionItem.modelData.description || ""
                            color: optionArea.containsMouse ? Qt.alpha(Common.Config.onPrimary, 0.7) : Common.Config.textMuted
                            font.family: Common.Config.fontFamily
                            font.pixelSize: Common.Config.type.bodySmall.size
                            visible: (optionItem.modelData.description || "").length > 0

                            Behavior on color {
                                ColorAnimation {
                                    duration: 150
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    id: optionArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.optionSelected(optionItem.modelData.value)
                }
            }
        }
    }
}
