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

        Rectangle {
            anchors.centerIn: parent
            color: Qt.alpha(root.iconColor, 0.12)
            height: parent.height
            radius: height / 2
            width: parent.width
            visible: root.icon !== ""
        }
        Text {
            anchors.centerIn: parent
            color: root.iconColor
            font.pixelSize: Config.type.headlineLarge.size
            text: root.icon
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: Config.space.none

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            color: Config.color.on_surface
            elide: Text.ElideRight
            font.family: Config.fontFamily
            font.pixelSize: Config.type.headlineSmall.size
            font.weight: Font.Bold
            text: root.title
        }
        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            color: Config.color.on_surface_variant
            elide: Text.ElideRight
            font.family: Config.fontFamily
            font.pixelSize: Config.type.labelMedium.size
            text: root.subtitle
            visible: root.subtitle !== ""
        }
    }
    Item {
        Layout.fillWidth: true
    }
}
