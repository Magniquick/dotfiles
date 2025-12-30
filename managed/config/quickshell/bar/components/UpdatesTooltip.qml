pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."

ColumnLayout {
    id: root

    property string actionText: ""
    property int count: 0
    readonly property int displayCount: root.count > 0 ? root.count : root.updatesCount
    property bool hasUpdates: false
    property string iconText: ""
    property bool refreshing: false
    readonly property var updateColors: [Config.m3.tertiary, Config.m3.secondary, Config.m3.flamingo, Config.m3.primary]
    property var updates: []
    readonly property int updatesCount: Array.isArray(root.updates) ? root.updates.length : 0

    signal actionRequested

    function getUpdateColor(index) {
        return root.updateColors[index % root.updateColors.length];
    }

    Layout.fillWidth: true
    implicitWidth: 360
    spacing: Config.space.sm

    RowLayout {
        id: headerRow

        Layout.fillWidth: true
        spacing: Config.space.md

        Item {
            height: Config.space.xxl * 2
            width: Config.space.xxl * 2

            Text {
                anchors.centerIn: parent
                color: root.hasUpdates ? Config.m3.tertiary : Config.m3.onSurfaceVariant
                font.family: Config.iconFontFamily
                font.pixelSize: Config.type.headlineLarge.size
                text: root.iconText
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: Config.space.none

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                color: Config.m3.onSurface
                elide: Text.ElideRight
                font.family: Config.fontFamily
                font.pixelSize: Config.type.headlineMedium.size
                font.weight: Font.Bold
                text: root.displayCount === 0 ? "Up to date" : (root.displayCount + (root.displayCount === 1 ? " update" : " updates"))
            }
            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                color: Config.m3.onSurfaceVariant
                elide: Text.ElideRight
                font.family: Config.fontFamily
                font.pixelSize: Config.type.labelMedium.size
                text: root.refreshing ? "Checking for updates…" : (root.hasUpdates ? "Packages ready to pull." : "No pending packages.")
            }
        }
        Item {
            Layout.fillWidth: true
        }
    }
    TooltipCard {
        content: [
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.sm

                Text {
                    color: Config.m3.onSurfaceVariant
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.bodySmall.size
                    text: root.displayCount === 0 ? "No updates available." : "Updates available, but details unavailable."
                    visible: root.displayCount === 0 || (root.displayCount > 0 && root.updatesCount === 0)
                }
                Flickable {
                    id: listFlick

                    Layout.fillWidth: true
                    clip: true
                    contentHeight: listColumn.implicitHeight
                    contentWidth: width
                    implicitHeight: Math.min(contentHeight, 280)
                    interactive: contentHeight > height
                    visible: root.updatesCount > 0

                    ScrollIndicator.vertical: ScrollIndicator {
                    }

                    Column {
                        id: listColumn

                        spacing: Config.space.sm
                        width: listFlick.width

                        Repeater {
                            model: root.updates

                            delegate: RowLayout {
                                required property int index
                                required property var modelData
                                property color rowColor: root.getUpdateColor(index)
                                readonly property int stripeWidth: Config.spaceHalfXs

                                spacing: Config.space.md
                                width: listColumn.width

                                Rectangle {
                                    Layout.fillHeight: true
                                    Layout.preferredHeight: Config.type.bodySmall.line + stripeWidth
                                    color: rowColor
                                    opacity: 0.9
                                    radius: Config.shape.corner.xs
                                    width: stripeWidth
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: Config.spaceHalfXs

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        color: rowColor
                                        elide: Text.ElideRight
                                        font.family: Config.fontFamily
                                        font.pixelSize: Config.type.bodyMedium.size
                                        font.weight: Font.Medium
                                        text: modelData && modelData.name ? String(modelData.name) : ""
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        color: Config.m3.onSurfaceVariant
                                        elide: Text.ElideRight
                                        font.family: Config.iconFontFamily
                                        font.pixelSize: Config.type.labelSmall.size
                                        text: modelData && modelData.detail ? String(modelData.detail) : ""
                                        visible: text !== ""
                                        wrapMode: Text.NoWrap
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
