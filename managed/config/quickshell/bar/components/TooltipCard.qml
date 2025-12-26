import ".."
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property alias content: contentColumn.data
    property int padding: Config.space.md
    property int spacing: Config.space.sm
    property color backgroundColor: Config.moduleBackgroundMuted
    property color borderColor: Config.outline
    property bool outlined: false

    Layout.fillWidth: true
    radius: Config.shape.corner.sm
    color: root.backgroundColor
    border.width: root.outlined ? 1 : 0
    border.color: root.borderColor
    antialiasing: true
    implicitWidth: contentColumn.implicitWidth + root.padding * 2
    implicitHeight: contentColumn.implicitHeight + root.padding * 2

    ColumnLayout {
        id: contentColumn

        anchors.fill: parent
        anchors.margins: root.padding
        spacing: root.spacing
    }
}
