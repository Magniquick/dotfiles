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
    property int detailsCount: 0
    property string errorText: ""
    property bool hasUpdates: false
    property string iconText: ""
    property bool refreshing: false
    readonly property var updateColors: [Config.color.tertiary, Config.color.secondary, Config.color.tertiary, Config.color.primary]
    property var updatesModel: null
    readonly property int updatesCount: root.detailsCount > 0 ? root.detailsCount : 0

    signal actionRequested

    function getUpdateColor(index) {
        // In Bound delegates (and during model resets), `index` can be undefined
        // briefly. Returning a concrete color avoids "Unable to assign [undefined]
        // to QColor" warnings.
        const i = Number(index);
        if (!Number.isFinite(i))
            return Config.color.primary;
        if (root.updateColors.length === 0)
            return Config.color.primary;
        return root.updateColors[i % root.updateColors.length] ?? Config.color.primary;
    }

    Layout.fillWidth: true
    implicitWidth: 360
    spacing: Config.space.sm

    RowLayout {
        id: headerRow

        Layout.fillWidth: true
        spacing: Config.space.md

        Item {
            Layout.preferredHeight: Config.space.xxl * 2
            Layout.preferredWidth: Config.space.xxl * 2
            implicitHeight: Config.space.xxl * 2
            implicitWidth: Config.space.xxl * 2

            Text {
                anchors.centerIn: parent
                color: root.hasUpdates ? Config.color.tertiary : Config.color.on_surface_variant
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
                color: Config.color.on_surface
                elide: Text.ElideRight
                font.family: Config.fontFamily
                font.pixelSize: Config.type.headlineMedium.size
                font.weight: Font.Bold
                text: root.displayCount === 0 ? "Up to date" : (root.displayCount + (root.displayCount === 1 ? " update" : " updates"))
            }
            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                color: Config.color.on_surface_variant
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
        backgroundColor: Config.color.on_secondary_fixed_variant
        borderColor: Config.color.outline_variant
        outlined: true
        content: [
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.sm

                Text {
                    color: Config.color.error
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.bodySmall.size
                    text: root.errorText
                    visible: root.errorText !== ""
                    wrapMode: Text.Wrap
                }
                Text {
                    color: Config.color.on_surface_variant
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

                    ScrollIndicator.vertical: ScrollIndicator {}

                    Column {
                        id: listColumn

                        spacing: Config.space.sm
                        width: listFlick.width

                        Repeater {
                            model: root.updatesModel

                            delegate: RowLayout {
                                id: updateRow
                                required property int index
                                // Explicit role bindings are required in `ComponentBehavior: Bound` delegates.
                                required property string name
                                required property string old_version
                                required property string new_version
                                readonly property string detail: old_version + "  →  " + new_version
                                property color rowColor: root.getUpdateColor(index)
                                readonly property int stripeWidth: Config.spaceHalfXs

                                spacing: Config.space.md
                                width: listColumn.width

                                Rectangle {
                                    Layout.fillHeight: true
                                    Layout.preferredHeight: Config.type.bodySmall.line + updateRow.stripeWidth
                                    color: updateRow.rowColor
                                    opacity: 0.9
                                    radius: Config.shape.corner.xs
                                    Layout.preferredWidth: updateRow.stripeWidth
                                    implicitWidth: updateRow.stripeWidth
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: Config.spaceHalfXs

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        color: updateRow.rowColor
                                        elide: Text.ElideRight
                                        font.family: Config.fontFamily
                                        font.pixelSize: Config.type.bodyMedium.size
                                        font.weight: Font.Medium
                                        text: updateRow.name
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        color: Config.color.on_surface_variant
                                        elide: Text.ElideRight
                                        font.family: Config.iconFontFamily
                                        font.pixelSize: Config.type.labelSmall.size
                                        text: updateRow.detail
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
