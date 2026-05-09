pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../common/materialkit" as MK
import "../../common" as Common
import "./" as Components

Item {
    id: root

    property var tool: ({})
    property bool expanded: false
    property bool rawExpanded: false
    readonly property bool showAssistantHeader: !!tool.show_header
    property string moodIcon: "\uf4c4"
    property string moodName: "Assistant"

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
    readonly property color diffAdditionColor: "#3fb950"
    readonly property color diffDeletionColor: Common.Config.color.error

    implicitWidth: parent ? parent.width : 320
    implicitHeight: wrapper.implicitHeight + 8

    function sectionTitle(section) {
        return String(section && section.title ? section.title : "Details");
    }

    function sectionContent(section) {
        return String(section && section.content ? section.content : "");
    }

    function htmlEscape(value) {
        return String(value || "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;");
    }

    function richSummary(value) {
        return htmlEscape(value).replace(/([+-]\d+)/g, function(match) {
            const color = match[0] === "+" ? root.diffAdditionColor : root.diffDeletionColor;
            return "<span style=\"color:" + color + "\">" + match + "</span>";
        });
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

        RowLayout {
            visible: root.showAssistantHeader
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            spacing: 6

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 7
                color: Qt.alpha(Common.Config.color.on_surface, 0.05)

                Text {
                    anchors.centerIn: parent
                    text: root.moodIcon
                    color: Common.Config.color.primary
                    font.family: Common.Config.iconFontFamily
                    font.pixelSize: 14
                }
            }

            Text {
                text: root.moodName || "ASSISTANT"
                color: Common.Config.color.on_surface_variant
                font {
                    family: Common.Config.fontFamily
                    pixelSize: 11
                    weight: Font.Bold
                    capitalization: Font.AllUppercase
                }
                opacity: 0.5
            }

            Item { Layout.fillWidth: true }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 0
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
                            id: summaryText
                            Layout.fillWidth: true
                            text: root.richSummary(summaryMetrics.elidedText)
                            textFormat: Text.RichText
                            color: Common.Config.color.on_surface
                            maximumLineCount: 1
                            font.family: Common.Config.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold

                            TextMetrics {
                                id: summaryMetrics
                                text: root.summary
                                font: summaryText.font
                                elide: Text.ElideRight
                                elideWidth: Math.max(0, summaryText.width)
                            }
                        }

                        Text {
                            id: subtitleText
                            Layout.fillWidth: true
                            visible: root.subtitle.length > 0
                            text: subtitleMetrics.elidedText
                            color: Common.Config.color.on_surface_variant
                            opacity: 0.78
                            maximumLineCount: 1
                            font.family: Common.Config.fontFamily
                            font.pixelSize: 11

                            TextMetrics {
                                id: subtitleMetrics
                                text: root.subtitle
                                font: subtitleText.font
                                elide: Text.ElideRight
                                elideWidth: Math.max(0, subtitleText.width)
                            }
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
                                duration: Common.Config.motion.duration.shortMs
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
                Layout.preferredHeight: visible ? implicitHeight : 0
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

                            Components.MessageCodeBlock {
                                readonly property bool isDiff: String(parent.modelData.kind || "") === "diff"
                                visible: isDiff
                                Layout.fillWidth: true
                                Layout.preferredHeight: visible ? implicitHeight : 0
                                code: root.sectionContent(parent.modelData)
                                language: "diff"
                            }

                            TextArea {
                                visible: String(parent.modelData.kind || "") !== "diff"
                                Layout.fillWidth: true
                                text: root.sectionContent(parent.modelData)
                                textFormat: TextEdit.PlainText
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
                        Layout.preferredHeight: visible
                            ? Math.min(260, Math.max(88, contentHeight + topPadding + bottomPadding + 2))
                            : 0
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
    }
}
