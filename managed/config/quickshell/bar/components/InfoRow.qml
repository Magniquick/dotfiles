import ".."
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root

    property string icon: ""
    property color iconColor: Config.textMuted
    property string label: ""
    property color labelColor: Config.textMuted
    property color leaderColor: Config.tooltipBorder
    property real leaderOpacity: 0.3
    property bool showLeader: true
    property string value: ""
    property color valueColor: Config.textColor

    spacing: Config.space.sm

    IconLabel {
        Layout.alignment: Qt.AlignVCenter
        color: root.iconColor
        font.pixelSize: Config.type.labelMedium.size
        font.weight: Config.type.labelMedium.weight
        text: root.icon
        visible: root.icon !== ""
    }
    Text {
        Layout.alignment: Qt.AlignVCenter
        color: root.labelColor
        font.family: Config.fontFamily
        font.pixelSize: Config.type.bodySmall.size
        font.weight: Config.type.bodySmall.weight
        text: root.label
    }
    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: root.leaderColor
        opacity: root.showLeader ? root.leaderOpacity : 0
        radius: 1
        visible: root.showLeader
    }
    Text {
        Layout.alignment: Qt.AlignVCenter
        color: root.valueColor
        font.family: Config.fontFamily
        font.pixelSize: Config.type.bodySmall.size
        font.weight: Config.type.bodySmall.weight
        horizontalAlignment: Text.AlignRight
        text: root.value
    }
}
