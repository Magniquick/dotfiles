pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."

ColumnLayout {
    id: root
    spacing: Config.space.md
    Layout.fillWidth: true

    property var systemUnits: []
    property var userUnits: []

    readonly property int systemCount: Array.isArray(root.systemUnits) ? root.systemUnits.length : 0
    readonly property int userCount: Array.isArray(root.userUnits) ? root.userUnits.length : 0
    readonly property int totalCount: root.systemCount + root.userCount
    readonly property bool showSystem: root.systemCount > 0
    readonly property bool showUser: root.userCount > 0

    function formatStatus(unitObj) {
        const active = unitObj && unitObj.active ? String(unitObj.active) : "";
        const sub = unitObj && unitObj.sub ? String(unitObj.sub) : "";
        if (active !== "" && sub !== "")
            return active === sub ? active : (active + " • " + sub);
        return active !== "" ? active : sub;
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Config.space.md

        Item {
            width: Config.space.xxl * 2
            height: Config.space.xxl * 2

            Text {
                anchors.centerIn: parent
                text: ""
                font.family: Config.iconFontFamily
                font.pixelSize: Config.type.headlineLarge.size
                color: Config.red
            }
        }

        ColumnLayout {
            spacing: Config.space.none

            Text {
                text: root.totalCount + (root.totalCount === 1 ? " Failed unit" : " Failed units")
                color: Config.textColor
                font.family: Config.fontFamily
                font.pixelSize: Config.type.headlineMedium.size
                font.weight: Font.Bold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Text {
                text: "system: " + root.systemCount + " • user: " + root.userCount
                color: Config.textMuted
                font.family: Config.fontFamily
                font.pixelSize: Config.type.labelMedium.size
                elide: Text.ElideRight
                Layout.fillWidth: true
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

                Flickable {
                    id: listFlick
                    clip: true
                    Layout.fillWidth: true
                    implicitHeight: Math.min(contentHeight, 260)
                    contentWidth: width
                    contentHeight: listColumn.implicitHeight
                    interactive: contentHeight > height

                    ScrollIndicator.vertical: ScrollIndicator {}

                    Column {
                        id: listColumn
                        width: listFlick.width
                        spacing: Config.space.sm

                        Text {
                            text: "No failed units."
                            color: Config.textMuted
                            font.family: Config.fontFamily
                            font.pixelSize: Config.type.bodySmall.size
                            visible: root.totalCount === 0
                        }

                        Column {
                            width: listColumn.width
                            spacing: Config.space.sm
                            visible: root.showSystem

                            Text {
                                text: "SYSTEM"
                                color: Config.primary
                                font.family: Config.fontFamily
                                font.pixelSize: Config.type.labelSmall.size
                                font.weight: Font.Black
                                font.letterSpacing: 1.5
                            }

                            Repeater {
                                model: root.systemUnits
                                delegate: RowLayout {
                                    required property var modelData
                                    spacing: Config.space.md
                                    width: listColumn.width
                                    readonly property int stripeWidth: Config.spaceHalfXs

                                    Rectangle {
                                        width: stripeWidth
                                        radius: Config.shape.corner.xs
                                        color: Config.red
                                        opacity: 0.8
                                        Layout.fillHeight: true
                                        Layout.preferredHeight: Config.type.bodySmall.line + stripeWidth
                                    }

                                    ColumnLayout {
                                        spacing: Config.space.none
                                        Layout.fillWidth: true

                                        Text {
                                            text: modelData.unit || ""
                                            color: Config.red
                                            font.family: Config.fontFamily
                                            font.pixelSize: Config.type.bodyMedium.size
                                            font.weight: Font.Medium
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text: modelData.description || ""
                                            color: Config.textMuted
                                            font.family: Config.fontFamily
                                            font.pixelSize: Config.type.bodySmall.size
                                            visible: text !== ""
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    Text {
                                        text: root.formatStatus(modelData)
                                        color: Config.textMuted
                                        font.family: Config.fontFamily
                                        font.pixelSize: Config.type.labelSmall.size
                                        opacity: 0.8
                                        visible: text !== ""
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: listColumn.width
                            height: 1
                            color: Config.outline
                            opacity: 0.18
                            visible: root.showSystem && root.showUser
                        }

                        Column {
                            width: listColumn.width
                            spacing: Config.space.sm
                            visible: root.showUser

                            Text {
                                text: "USER"
                                color: Config.primary
                                font.family: Config.fontFamily
                                font.pixelSize: Config.type.labelSmall.size
                                font.weight: Font.Black
                                font.letterSpacing: 1.5
                            }

                            Repeater {
                                model: root.userUnits
                                delegate: RowLayout {
                                    required property var modelData
                                    spacing: Config.space.md
                                    width: listColumn.width
                                    readonly property int stripeWidth: Config.spaceHalfXs

                                    Rectangle {
                                        width: stripeWidth
                                        radius: Config.shape.corner.xs
                                        color: Config.red
                                        opacity: 0.8
                                        Layout.fillHeight: true
                                        Layout.preferredHeight: Config.type.bodySmall.line + stripeWidth
                                    }

                                    ColumnLayout {
                                        spacing: Config.space.none
                                        Layout.fillWidth: true

                                        Text {
                                            text: modelData.unit || ""
                                            color: Config.red
                                            font.family: Config.fontFamily
                                            font.pixelSize: Config.type.bodyMedium.size
                                            font.weight: Font.Medium
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text: modelData.description || ""
                                            color: Config.textMuted
                                            font.family: Config.fontFamily
                                            font.pixelSize: Config.type.bodySmall.size
                                            visible: text !== ""
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    Text {
                                        text: root.formatStatus(modelData)
                                        color: Config.textMuted
                                        font.family: Config.fontFamily
                                        font.pixelSize: Config.type.labelSmall.size
                                        opacity: 0.8
                                        visible: text !== ""
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        ]
    }
}
