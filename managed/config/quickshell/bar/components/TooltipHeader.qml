import QtQuick
import QtQuick.Layouts
import ".."

RowLayout {
    id: root

    property string icon: ""
    property color iconColor: Config.color.on_surface
    property string title: ""
    property string subtitle: ""

    Layout.fillWidth: true
    spacing: Config.space.md

    Item {
        Layout.preferredHeight: Config.space.xxl * 2
        Layout.preferredWidth: Config.space.xxl * 2

        Text {
            anchors.centerIn: parent
            color: root.iconColor
            font.pixelSize: Config.type.headlineLarge.size
            text: root.icon
        }
    }
    ColumnLayout {
        spacing: Config.space.none

        Text {
            Layout.fillWidth: true
            color: Config.color.on_surface
            elide: Text.ElideRight
            font.family: Config.fontFamily
            font.pixelSize: Config.type.headlineSmall.size
            font.weight: Font.Bold
            text: root.title
        }
        Text {
            color: Config.color.on_surface_variant
            font.family: Config.fontFamily
            font.pixelSize: Config.type.labelMedium.size
            text: root.subtitle
        }
    }
    Item {
        Layout.fillWidth: true
    }
}
