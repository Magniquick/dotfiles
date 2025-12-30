import ".."
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property color backgroundColor: Config.moduleBackgroundMuted
    property color borderColor: Config.m3.outline
    property alias content: contentColumn.data
    property bool outlined: false
    property int padding: Config.space.md
    property int spacing: Config.space.sm

    Layout.fillWidth: true
    antialiasing: true
    border.color: root.borderColor
    border.width: root.outlined ? 1 : 0
    color: root.backgroundColor
    implicitHeight: contentColumn.implicitHeight + root.padding * 2
    implicitWidth: contentColumn.implicitWidth + root.padding * 2
    radius: Config.shape.corner.sm

    ColumnLayout {
        id: contentColumn

        anchors.fill: parent
        anchors.margins: root.padding
        spacing: root.spacing
    }
}
