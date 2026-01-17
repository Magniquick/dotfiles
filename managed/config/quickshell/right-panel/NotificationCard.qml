import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "./common" as Common

Item {
    id: root
    property var entry
    property bool popup: false
    signal dismissRequested()

    width: 320
    implicitHeight: card.implicitHeight

    readonly property bool hovered: cardHover.containsMouse || closeArea.containsMouse
    readonly property color urgencyColor: {
        if (!entry || !entry.urgency) {
            return Common.Config.primary;
        }
        if (entry.urgency === "critical") {
            return Common.Config.error;
        }
        if (entry.urgency === "low") {
            return Common.Config.onSurfaceVariant;
        }
        return Common.Config.primary;
    }

    Rectangle {
        id: card
        anchors {
            left: parent.left
            right: parent.right
        }
        color: root.hovered
            ? Common.Config.surfaceContainerHighest
            : Common.Config.surfaceContainerHigh
        radius: Common.Config.shape.corner.lg
        border.width: 1
        border.color: Common.Config.outline
        implicitHeight: contentColumn.implicitHeight + Common.Config.space.sm * 2

        Behavior on color {
            ColorAnimation {
                duration: Common.Config.motion.duration.shortMs
                easing.type: Common.Config.motion.easing.standard
            }
        }

        MouseArea {
            id: cardHover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        Rectangle {
            width: 4
            color: root.urgencyColor
            radius: 2
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
                leftMargin: Common.Config.space.xs
                topMargin: Common.Config.space.xs
                bottomMargin: Common.Config.space.xs
            }
        }

        ColumnLayout {
            id: contentColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Common.Config.space.sm
            }
            spacing: Common.Config.space.xs

            RowLayout {
                Layout.fillWidth: true
                spacing: Common.Config.space.xs

                Rectangle {
                    visible: iconImage.visible
                    width: 28
                    height: 28
                    radius: Common.Config.shape.corner.sm
                    color: Common.Config.surfaceVariant

                    Image {
                        id: iconImage
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        fillMode: Image.PreserveAspectFit
                        source: entry && entry.iconSource ? entry.iconSource : ""
                        visible: source.length > 0
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: entry && entry.appName ? entry.appName : "Notification"
                        color: Common.Config.textMuted
                        font.family: Common.Config.fontFamily
                        font.pixelSize: Common.Config.type.labelMedium.size
                        font.weight: Common.Config.type.labelMedium.weight
                        elide: Text.ElideRight
                    }

                    Text {
                        text: entry && entry.summary ? entry.summary : ""
                        color: Common.Config.textColor
                        font.family: Common.Config.fontFamily
                        font.pixelSize: Common.Config.type.titleSmall.size
                        font.weight: Common.Config.type.titleSmall.weight
                        wrapMode: Text.WordWrap
                        visible: text.length > 0
                    }
                }

                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: closeArea.containsMouse
                        ? Qt.alpha(Common.ColorPalette.palette.overlay2, 0.25)
                        : Common.Config.surfaceVariant

                    Text {
                        anchors.centerIn: parent
                        text: "x"
                        color: Common.Config.textMuted
                        font.family: Common.Config.fontFamily
                        font.pixelSize: Common.Config.type.labelMedium.size
                        font.weight: Common.Config.type.labelMedium.weight
                    }

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.dismissRequested()
                    }
                }
            }

            Text {
                text: entry && entry.body ? entry.body : ""
                color: Common.Config.textColor
                font.family: Common.Config.fontFamily
                font.pixelSize: Common.Config.type.bodySmall.size
                font.weight: Common.Config.type.bodySmall.weight
                wrapMode: Text.WordWrap
                visible: text.length > 0
            }
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: Common.Config.motion.duration.shortMs
            easing.type: Common.Config.motion.easing.standard
        }
    }
}
