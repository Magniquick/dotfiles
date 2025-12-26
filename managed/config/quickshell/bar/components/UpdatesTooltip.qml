pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."

ColumnLayout {
    id: root
    spacing: Config.space.sm
    Layout.fillWidth: true
    implicitWidth: 360

    property var updates: []
    property int count: 0
    property bool hasUpdates: false
    property string iconText: ""
    property string actionText: ""
    property bool refreshing: false
    signal actionRequested

    readonly property int updatesCount: Array.isArray(root.updates) ? root.updates.length : 0
    readonly property int displayCount: root.count > 0 ? root.count : root.updatesCount
    readonly property var updateColors: [Config.lavender, Config.pink, Config.flamingo, Config.primary]

    function getUpdateColor(index) {
        return root.updateColors[index % root.updateColors.length];
    }

    RowLayout {
        id: headerRow
        Layout.fillWidth: true
        spacing: Config.space.md

        Item {
            width: Config.space.xxl * 2
            height: Config.space.xxl * 2

            Text {
                anchors.centerIn: parent
                text: root.iconText
                font.family: Config.iconFontFamily
                font.pixelSize: Config.type.headlineLarge.size
                color: root.hasUpdates ? Config.lavender : Config.textMuted
            }
        }

        ColumnLayout {
            spacing: Config.space.none
            Layout.fillWidth: true
            Layout.minimumWidth: 0

            Text {
                text: root.displayCount === 0 ? "Up to date" : (root.displayCount + (root.displayCount === 1 ? " update" : " updates"))
                color: Config.textColor
                font.family: Config.fontFamily
                font.pixelSize: Config.type.headlineMedium.size
                font.weight: Font.Bold
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.minimumWidth: 0
            }

            Text {
                text: root.refreshing ? "Checking for updates…" : (root.hasUpdates ? "Packages ready to pull." : "No pending packages.")
                color: Config.textMuted
                font.family: Config.fontFamily
                font.pixelSize: Config.type.labelMedium.size
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.minimumWidth: 0
            }
        }

        Item {
            Layout.fillWidth: true
        }
    }

    TooltipCard {
        content: [
            ColumnLayout {
                spacing: Config.space.sm
                Layout.fillWidth: true

                Text {
                    text: root.displayCount === 0 ? "No updates available." : "Updates available, but details unavailable."
                    color: Config.textMuted
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.bodySmall.size
                    visible: root.displayCount === 0 || (root.displayCount > 0 && root.updatesCount === 0)
                }

                Flickable {
                    id: listFlick
                    clip: true
                    Layout.fillWidth: true
                    implicitHeight: Math.min(contentHeight, 280)
                    contentWidth: width
                    contentHeight: listColumn.implicitHeight
                    interactive: contentHeight > height
                    visible: root.updatesCount > 0

                    ScrollIndicator.vertical: ScrollIndicator {}

                    Column {
                        id: listColumn
                        width: listFlick.width
                        spacing: Config.space.sm

                        Repeater {
                            model: root.updates
                            delegate: RowLayout {
                                required property var modelData
                                required property int index
                                spacing: Config.space.md
                                width: listColumn.width
                                property color rowColor: root.getUpdateColor(index)
                                readonly property int stripeWidth: Config.spaceHalfXs

                                Rectangle {
                                    width: stripeWidth
                                    radius: Config.shape.corner.xs
                                    color: rowColor
                                    opacity: 0.9
                                    Layout.fillHeight: true
                                    Layout.preferredHeight: Config.type.bodySmall.line + stripeWidth
                                }

                                ColumnLayout {
                                    spacing: Config.spaceHalfXs
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0

                                    Text {
                                        text: modelData && modelData.name ? String(modelData.name) : ""
                                        color: rowColor
                                        font.family: Config.fontFamily
                                        font.pixelSize: Config.type.bodyMedium.size
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                    }

                                    Text {
                                        text: modelData && modelData.detail ? String(modelData.detail) : ""
                                        color: Config.textMuted
                                        font.family: Config.iconFontFamily
                                        font.pixelSize: Config.type.labelSmall.size
                                        visible: text !== ""
                                        wrapMode: Text.NoWrap
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                    }
                                }
                            }
                        }
                    }
                }
            }
        ]
    }

    TooltipActionsRow {
        id: actionsRow
        visible: root.actionText !== ""

        ActionChip {
            text: root.actionText
            onClicked: root.actionRequested()
        }
    }
}
