import ".."
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property color accentColor: Config.accent
    property color backgroundColor: Config.moduleBackgroundHover
    property int barHeight: Math.max(1, Config.space.xs)
    property color borderColor: Config.tooltipBorder
    property int borderWidth: Config.tooltipBorderWidth
    property color chipColor: Config.moduleBackgroundMuted
    property string chipText: ""
    property color chipTextColor: Config.textColor
    property real fillRatio: 0
    readonly property int gutter: Config.spaceHalfXs
    property string icon: ""
    property string label: ""
    property color labelColor: Config.textMuted
    property int padding: Config.space.sm
    property string secondaryValue: ""
    property bool showFill: true
    property string tertiaryValue: ""
    property string value: ""
    property color valueColor: Config.textColor

    antialiasing: true
    border.color: root.borderColor
    border.width: root.borderWidth
    color: root.backgroundColor
    implicitHeight: contentLayout.implicitHeight + root.padding * 2 + (root.showFill ? root.barHeight + root.gutter : 0)
    implicitWidth: contentLayout.implicitWidth + root.padding * 2
    radius: Math.max(Config.shape.corner.sm, Config.tooltipRadius - Config.space.xs)

    ColumnLayout {
        id: contentLayout

        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding + (root.showFill ? root.barHeight + root.gutter : 0)
        anchors.left: parent.left
        anchors.leftMargin: root.padding
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        anchors.top: parent.top
        anchors.topMargin: root.padding
        spacing: root.gutter

        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            spacing: Math.round(Config.space.sm / 2)

            IconLabel {
                Layout.alignment: Qt.AlignVCenter
                color: root.labelColor
                font.pixelSize: Math.max(Config.type.labelSmall.size, Config.iconSize - Config.space.xs)
                text: root.icon
                visible: root.icon !== ""
            }
            Text {
                Layout.alignment: Qt.AlignVCenter
                color: root.labelColor
                font.family: Config.fontFamily
                font.letterSpacing: 1
                font.pixelSize: Math.max(Config.type.labelSmall.size, Config.fontSize - Config.space.xs)
                font.weight: Font.DemiBold
                text: root.label
            }
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: Math.max(Config.type.labelSmall.line, chipTextMetrics.implicitHeight + Config.spaceHalfXs)
                Layout.preferredWidth: chipTextMetrics.implicitWidth + Config.space.sm
                border.color: Qt.rgba(root.chipColor.r, root.chipColor.g, root.chipColor.b, 0.24)
                border.width: 1
                color: root.chipColor
                radius: Config.shape.corner.xs
                visible: root.chipText !== ""

                Text {
                    id: chipTextMetrics

                    anchors.centerIn: parent
                    color: root.chipTextColor
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.labelSmall.size - 2
                    font.weight: Font.Medium
                    renderType: Text.NativeRendering
                    text: root.chipText
                }
            }
            Item {
                Layout.fillWidth: true
            }
        }
        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: (root.secondaryValue !== "" || root.tertiaryValue !== "") ? root.gutter / 2 : 0

            Text {
                Layout.alignment: Qt.AlignVCenter
                color: root.valueColor
                font.family: Config.fontFamily
                font.pixelSize: Math.max(Config.type.labelSmall.size + Math.round(root.gutter / 2), Config.fontSize)
                text: root.value
            }
            Text {
                Layout.alignment: Qt.AlignVCenter
                color: root.labelColor
                font.family: Config.fontFamily
                font.pixelSize: Config.type.bodySmall.size - 1
                text: root.secondaryValue
                visible: root.secondaryValue !== ""
            }
            Text {
                Layout.alignment: Qt.AlignVCenter
                color: root.labelColor
                font.family: Config.fontFamily
                font.pixelSize: Config.type.bodySmall.size - 1
                text: root.tertiaryValue
                visible: root.tertiaryValue !== ""
            }
        }
    }
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        anchors.left: parent.left
        anchors.leftMargin: root.padding
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        color: root.borderColor
        height: root.barHeight
        opacity: 0.28
        radius: root.barHeight / 2
        visible: root.showFill
    }
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        anchors.left: parent.left
        anchors.leftMargin: root.padding
        color: root.accentColor
        height: root.barHeight
        radius: root.barHeight / 2
        visible: root.showFill
        width: Math.max(0, Math.min(1, root.fillRatio)) * (parent.width - root.padding * 2)
    }
}
