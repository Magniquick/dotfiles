import ".."
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property string label: ""
    property string value: ""
    property string icon: ""
    property color labelColor: Config.textMuted
    property color valueColor: Config.textColor
    property color accentColor: Config.accent
    property color backgroundColor: Config.moduleBackgroundHover
    property color borderColor: Config.tooltipBorder
    property int borderWidth: Config.tooltipBorderWidth
    property bool showFill: true
    property real fillRatio: 0
    property int padding: Config.space.sm
    property int barHeight: Math.max(1, Config.space.xs)
    readonly property int gutter: Config.spaceHalfXs
    property string secondaryValue: ""
    property string tertiaryValue: ""
    property string chipText: ""
    property color chipColor: Config.moduleBackgroundMuted
    property color chipTextColor: Config.textColor

    radius: Math.max(Config.shape.corner.sm, Config.tooltipRadius - Config.space.xs)
    color: root.backgroundColor
    border.width: root.borderWidth
    border.color: root.borderColor
    antialiasing: true
    implicitWidth: contentLayout.implicitWidth + root.padding * 2
    implicitHeight: contentLayout.implicitHeight + root.padding * 2 + (root.showFill ? root.barHeight + root.gutter : 0)

    ColumnLayout {
        id: contentLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding
        anchors.topMargin: root.padding
        anchors.bottomMargin: root.padding + (root.showFill ? root.barHeight + root.gutter : 0)
        spacing: root.gutter

        RowLayout {
            spacing: Math.round(Config.space.sm / 2)
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter

            IconLabel {
                visible: root.icon !== ""
                text: root.icon
                color: root.labelColor
                font.pixelSize: Math.max(Config.type.labelSmall.size, Config.iconSize - Config.space.xs)
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text: root.label
                color: root.labelColor
                font.family: Config.fontFamily
                font.pixelSize: Math.max(Config.type.labelSmall.size, Config.fontSize - Config.space.xs)
                font.weight: Font.DemiBold
                font.letterSpacing: 1
                Layout.alignment: Qt.AlignVCenter
            }

            Rectangle {
                visible: root.chipText !== ""
                radius: Config.shape.corner.xs
                color: root.chipColor
                border.color: Qt.rgba(root.chipColor.r, root.chipColor.g, root.chipColor.b, 0.24)
                border.width: 1
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: Math.max(Config.type.labelSmall.line, chipTextMetrics.implicitHeight + Config.spaceHalfXs)
                Layout.preferredWidth: chipTextMetrics.implicitWidth + Config.space.sm

                Text {
                    id: chipTextMetrics

                    anchors.centerIn: parent
                    text: root.chipText
                    color: root.chipTextColor
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.labelSmall.size - 2
                    font.weight: Font.Medium
                    renderType: Text.NativeRendering
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }

        ColumnLayout {
            spacing: (root.secondaryValue !== "" || root.tertiaryValue !== "") ? root.gutter / 2 : 0
            Layout.alignment: Qt.AlignVCenter

            Text {
                text: root.value
                color: root.valueColor
                font.family: Config.fontFamily
                font.pixelSize: Math.max(Config.type.labelSmall.size + Math.round(root.gutter / 2), Config.fontSize)
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                visible: root.secondaryValue !== ""
                text: root.secondaryValue
                color: root.labelColor
                font.family: Config.fontFamily
                font.pixelSize: Config.type.bodySmall.size - 1
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                visible: root.tertiaryValue !== ""
                text: root.tertiaryValue
                color: root.labelColor
                font.family: Config.fontFamily
                font.pixelSize: Config.type.bodySmall.size - 1
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    Rectangle {
        visible: root.showFill
        height: root.barHeight
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding
        anchors.bottomMargin: root.padding
        color: root.borderColor
        opacity: 0.28
        radius: root.barHeight / 2
    }

    Rectangle {
        visible: root.showFill
        height: root.barHeight
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.padding
        anchors.bottomMargin: root.padding
        width: Math.max(0, Math.min(1, root.fillRatio)) * (parent.width - root.padding * 2)
        color: root.accentColor
        radius: root.barHeight / 2
    }
}
