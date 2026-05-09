pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../common/materialkit" as MK
import "../../common" as Common

Item {
    id: root

    property var tool: ({})
    property bool expanded: false
    property bool rawExpanded: false

    readonly property string status: String(tool.status || "")
    readonly property bool isError: !!tool.is_error || status === "error"
    readonly property bool isRunning: status === "running"
    readonly property string summary: String(tool.summary || tool.tool_name || "tool call")
    readonly property string subtitle: String(tool.subtitle || "")
    readonly property string iconText: String(tool.icon || (isError ? "!" : "•"))
    readonly property var detailSections: tool.detail_sections || []
    readonly property string agentPayload: String(tool.agent_payload || "")
    readonly property bool hasRaw: agentPayload.length > 0
    readonly property color rowColor: isError ? Common.Config.color.error : Common.Config.color.primary
    readonly property color onRowColor: isError ? Common.Config.color.on_error : Common.Config.color.on_primary

    implicitWidth: parent ? parent.width : 320
    implicitHeight: wrapper.implicitHeight + separator.height + 12

    function sectionTitle(section) {
        return String(section && section.title ? section.title : "Details");
    }

    function sectionContent(section) {
        return String(section && section.content ? section.content : "");
    }

    ColumnLayout {
        id: wrapper
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: 0
            rightMargin: 0
        }
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.max(46, headerRow.implicitHeight + 16)
            radius: Common.Config.shape.corner.sm
            color: Qt.alpha(Common.Config.color.surface_container_highest, root.isRunning ? 0.72 : 0.58)
            border.width: 1
            border.color: Qt.alpha(root.rowColor, root.isError ? 0.42 : 0.22)

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expanded = !root.expanded
            }

            RowLayout {
                id: headerRow
                anchors.fill: parent
                anchors.margins: 8
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    Layout.alignment: Qt.AlignVCenter
                    radius: 6
                    color: Qt.alpha(root.rowColor, 0.16)

                    Text {
                        anchors.centerIn: parent
                        text: root.iconText
                        color: root.rowColor
                        font.family: Common.Config.iconFontFamily
                        font.pixelSize: 14
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: root.summary
                        color: Common.Config.color.on_surface
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.family: Common.Config.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.subtitle.length > 0
                        text: root.subtitle
                        color: Common.Config.color.on_surface_variant
                        opacity: 0.78
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.family: Common.Config.fontFamily
                        font.pixelSize: 11
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: "\uf105"
                    color: Common.Config.color.on_surface_variant
                    opacity: 0.75
                    rotation: root.expanded ? 90 : 0
                    font.family: Common.Config.iconFontFamily
                    font.pixelSize: 14

                    Behavior on rotation {
                        NumberAnimation {
                            duration: Common.Config.motion.duration.short
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.expanded
            implicitHeight: detailColumn.implicitHeight + 18
            radius: Common.Config.shape.corner.sm
            color: Qt.alpha(Common.Config.color.surface_container_low, 0.82)
            border.width: 1
            border.color: Qt.alpha(root.rowColor, 0.14)

            ColumnLayout {
                id: detailColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 9
                }
                spacing: 9

                Repeater {
                    model: root.detailSections

                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: root.sectionTitle(parent.modelData).toUpperCase()
                            color: Common.Config.color.on_surface_variant
                            opacity: 0.62
                            font.family: Common.Config.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        TextArea {
                            Layout.fillWidth: true
                            text: root.sectionContent(parent.modelData)
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextArea.Wrap
                            color: Common.Config.color.on_surface
                            selectedTextColor: Common.Config.color.on_primary
                            selectionColor: Common.Config.color.primary
                            font.family: String(parent.modelData.kind || "") === "text"
                                ? Common.Config.fontFamily
                                : "JetBrains Mono"
                            font.pixelSize: 11
                            padding: 8
                            background: Rectangle {
                                radius: Common.Config.shape.corner.xs
                                color: Common.Config.color.surface
                                border.width: 1
                                border.color: Qt.alpha(Common.Config.color.on_surface, 0.07)
                            }
                        }
                    }
                }

                Text {
                    visible: root.detailSections.length === 0
                    text: root.isRunning ? "Waiting for result..." : "No cleaned details."
                    color: Common.Config.color.on_surface_variant
                    opacity: 0.7
                    font.family: Common.Config.fontFamily
                    font.pixelSize: 12
                }

                Rectangle {
                    visible: root.hasRaw
                    Layout.preferredWidth: rawLabel.implicitWidth + 22
                    Layout.preferredHeight: 28
                    radius: Common.Config.shape.corner.sm
                    color: rawArea.containsMouse
                        ? Qt.alpha(Common.Config.color.primary, 0.16)
                        : Qt.alpha(Common.Config.color.primary, 0.09)
                    border.width: 1
                    border.color: Qt.alpha(Common.Config.color.primary, rawArea.containsMouse ? 0.42 : 0.24)

                    Text {
                        id: rawLabel
                        anchors.centerIn: parent
                        text: root.rawExpanded ? "Hide Codex payload" : "Show Codex payload"
                        color: Common.Config.color.primary
                        font.family: Common.Config.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    MK.HybridRipple {
                        anchors.fill: parent
                        color: Common.Config.color.primary
                        pressX: rawArea.pressX
                        pressY: rawArea.pressY
                        pressed: rawArea.pressed
                        radius: parent.radius
                        stateOpacity: rawArea.containsMouse ? Common.Config.state.hoverOpacity : 0
                    }

                    MouseArea {
                        id: rawArea
                        property real pressX: width / 2
                        property real pressY: height / 2
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.rawExpanded = !root.rawExpanded
                        onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
                    }
                }

                TextArea {
                    Layout.fillWidth: true
                    visible: root.hasRaw && root.rawExpanded
                    text: root.agentPayload
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextArea.Wrap
                    color: Common.Config.color.on_surface
                    selectedTextColor: Common.Config.color.on_primary
                    selectionColor: Common.Config.color.primary
                    font.family: "JetBrains Mono"
                    font.pixelSize: 11
                    padding: 8
                    background: Rectangle {
                        radius: Common.Config.shape.corner.xs
                        color: Common.Config.color.surface
                        border.width: 1
                        border.color: Qt.alpha(Common.Config.color.on_surface, 0.07)
                    }
                }
            }
        }
    }

    Rectangle {
        id: separator
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 1
        color: Qt.alpha(Common.Config.color.on_surface, 0.05)
    }
}
