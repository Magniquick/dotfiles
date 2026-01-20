import QtQuick
import QtQuick.Layouts
import "../common" as Common

ColumnLayout {
    id: root
    property var entry
    property bool showCloseButton: false
    signal closeClicked

    readonly property color urgencyColor: {
        if (!entry || !entry.urgency)
            return "#69bfce";
        if (entry.urgency === "critical")
            return "#E34F4F";
        if (entry.urgency === "low")
            return "#5599E2";
        return "#69bfce";
    }

    spacing: 4

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
            text: "\ueb05"
            color: root.urgencyColor
            font.family: Common.Config.iconFontFamily
            font.pointSize: 12
            Layout.alignment: Qt.AlignBaseline
        }

        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignBaseline
            text: root.entry && root.entry.summary ? root.entry.summary : ""
            color: Common.ColorPalette.palette.text
            font.family: "Kyok"
            font.weight: Font.Medium
            font.pointSize: 12
            wrapMode: Text.WordWrap
            visible: text.length > 0
        }

        Rectangle {
            implicitWidth: 20
            implicitHeight: 20
            radius: 10
            color: closeArea.containsMouse ? Qt.alpha(Common.ColorPalette.palette.overlay2, 0.25) : "transparent"
            Layout.alignment: Qt.AlignTop
            visible: root.showCloseButton

            Behavior on color {
                ColorAnimation {
                    duration: Common.Config.motion.duration.shortMs
                    easing.type: Common.Config.motion.easing.standard
                }
            }

            Text {
                anchors.centerIn: parent
                text: "\uf00d"
                color: closeArea.containsMouse ? Common.ColorPalette.palette.text : Common.ColorPalette.palette.surface1
                font.family: Common.Config.iconFontFamily
                font.pixelSize: 10

                Behavior on color {
                    ColorAnimation {
                        duration: Common.Config.motion.duration.shortMs
                        easing.type: Common.Config.motion.easing.standard
                    }
                }
            }

            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closeClicked()
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: root.entry && root.entry.body && root.entry.body.length > 0

        Text {
            text: "\uea9c"
            color: Common.ColorPalette.palette.surface1
            font.family: Common.Config.iconFontFamily
            font.pointSize: 12
            Layout.alignment: Qt.AlignBaseline
        }

        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignBaseline
            text: root.entry && root.entry.body ? root.entry.body : ""
            color: Common.ColorPalette.palette.text
            font.family: "Kyok"
            font.weight: Font.Medium
            font.pointSize: 12
            wrapMode: Text.WordWrap
        }
    }
}
