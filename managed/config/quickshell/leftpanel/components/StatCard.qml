import QtQuick
import QtQuick.Layouts
import "../../common" as Common

Item {
    id: root
    property string title: ""
    property string value: ""
    property string icon: ""
    property string subtext: ""
    property color accent: Common.Config.color.primary
    property bool centerText: false
    property bool centerContent: false

    implicitHeight: 80
    Layout.fillWidth: true

    Rectangle {
        anchors.fill: parent
        radius: Common.Config.shape.corner.lg
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(Common.Config.color.on_surface, 0.1)
        clip: true

        Item {
            anchors.fill: parent

            RowLayout {
                id: statRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: root.centerContent ? parent.horizontalCenter : undefined
                anchors.left: root.centerContent ? undefined : parent.left
                anchors.right: root.centerContent ? undefined : parent.right
                anchors.leftMargin: root.centerContent ? 0 : Common.Config.space.sm
                anchors.rightMargin: root.centerContent ? 0 : Common.Config.space.sm
                spacing: Common.Config.space.sm

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    implicitWidth: 36
                    implicitHeight: 36
                    radius: Common.Config.shape.corner.sm
                    color: Qt.alpha(Common.Config.color.on_surface, 0.05)

                    Text {
                        anchors.centerIn: parent
                        text: root.icon
                        color: root.accent
                        font.family: Common.Config.iconFontFamily
                        font.pixelSize: 16
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: !root.centerContent
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    Item {
                        Layout.fillHeight: true
                        visible: !root.centerContent
                    }

                    Text {
                        Layout.fillWidth: !root.centerContent
                        text: root.value
                        color: Common.Config.color.on_surface
                        font.family: Common.Config.fontFamily
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                        horizontalAlignment: root.centerText ? Text.AlignHCenter : Text.AlignLeft
                    }

                    Text {
                        Layout.fillWidth: !root.centerContent
                        text: root.title
                        color: Common.Config.color.on_surface_variant
                        font.family: Common.Config.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.capitalization: Font.AllUppercase
                        opacity: 0.5
                        elide: Text.ElideRight
                        horizontalAlignment: root.centerText ? Text.AlignHCenter : Text.AlignLeft
                    }

                    Text {
                        Layout.fillWidth: !root.centerContent
                        visible: root.subtext !== ""
                        text: root.subtext
                        color: Common.Config.color.on_surface_variant
                        font.family: Common.Config.fontFamily
                        font.pixelSize: 8
                        opacity: 0.3
                        elide: Text.ElideRight
                        horizontalAlignment: root.centerText ? Text.AlignHCenter : Text.AlignLeft
                    }

                    Item {
                        Layout.fillHeight: true
                        visible: !root.centerContent
                    }
                }
            }
        }
    }
}
