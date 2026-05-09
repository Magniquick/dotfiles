pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../common" as Common

Item {
    id: root

    property var tool: ({})
    property bool expanded: false
    readonly property bool showAssistantHeader: !!tool.show_header
    property string moodIcon: "\uf4c4"
    property string moodName: "Assistant"

    signal expandedChangeRequested(bool expanded)

    readonly property string status: String(tool.status || "")
    readonly property bool isError: !!tool.is_error || status === "error"
    readonly property bool isRunning: status === "running"
    readonly property string serverId: String(tool.server_id || namespaceServerId(tool.namespace || ""))
    readonly property string serverLabel: String(tool.server_label || serverDisplayName(serverId))
    readonly property string toolTitle: String(tool.tool_title || tool.tool_name || "tool call")
    readonly property string namespaceName: String(tool.namespace || "")
    readonly property string risk: String(tool.risk || "")
    readonly property bool readOnly: !!tool.read_only
    readonly property int durationMs: Number(tool.duration_ms || 0)
    readonly property string summary: String(tool.summary || toolTitle)
    readonly property string subtitle: String(tool.subtitle || "")
    readonly property string iconText: resolvedIconText()
    readonly property var detailSections: tool.detail_sections || []
    readonly property color rowColor: isError ? Common.Config.color.error : Common.Config.color.primary
    readonly property color onRowColor: isError ? Common.Config.color.on_error : Common.Config.color.on_primary
    readonly property color diffAdditionColor: "#3fb950"
    readonly property color diffDeletionColor: Common.Config.color.error
    readonly property int detailPreviewChars: 6000
    readonly property int detailPreviewLines: 80

    implicitWidth: parent ? parent.width : 320
    implicitHeight: wrapper.implicitHeight + 8

    function sectionTitle(section) {
        return String(section && section.title ? section.title : "Details");
    }

    function sectionContent(section) {
        return String(section && section.content ? section.content : "");
    }

    function sectionKind(section) {
        return String(section && section.kind ? section.kind : "text");
    }

    function boundedText(value, charLimit, lineLimit) {
        let text = String(value || "").replace(/\n+$/, "");
        let truncated = false;

        if (charLimit > 0 && text.length > charLimit) {
            text = text.slice(0, charLimit);
            truncated = true;
        }

        if (lineLimit > 0) {
            const lines = text.split("\n");
            if (lines.length > lineLimit) {
                text = lines.slice(0, lineLimit).join("\n");
                truncated = true;
            }
        }

        return truncated ? text + "\n[truncated]" : text;
    }

    function sectionPreview(section) {
        return boundedText(sectionContent(section), detailPreviewChars, detailPreviewLines);
    }

    function detailFontFamily(kind) {
        return kind === "text" ? Common.Config.fontFamily : "JetBrains Mono";
    }

    function namespaceServerId(namespace) {
        const clean = String(namespace || "");
        if (clean.indexOf("mcp__") !== 0 || clean.lastIndexOf("__") !== clean.length - 2)
            return "";
        return clean.slice(5, -2);
    }

    function serverDisplayName(server) {
        switch (String(server || "")) {
        case "todoist":
            return "Todoist";
        case "email":
            return "Email";
        case "builtin":
            return "Built-in";
        default:
            return String(server || "");
        }
    }

    function resolvedIconText() {
        if (root.isError)
            return "!";

        const toolName = String(root.tool.tool_name || "");
        const server = root.serverId;

        if (toolName === "shell_command" || toolName === "shell_exec" || toolName === "builtin__shell_command" || toolName === "builtin__shell_exec")
            return "$";

        if (toolName === "apply_patch" || toolName === "builtin__apply_patch")
            return "±";

        if (server === "email" || toolName.indexOf("email_") === 0 || toolName.indexOf("email__") === 0)
            return "\uf0e0";

        if (server === "todoist" || toolName.indexOf("todoist__") === 0)
            return "󰄭";

        return "•";
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
                    onClicked: root.expandedChangeRequested(!root.expanded)
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
                            text: root.richSummary(root.summary)
                            textFormat: Text.RichText
                            color: Common.Config.color.on_surface
                            clip: true
                            maximumLineCount: 1
                            font.family: Common.Config.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        Text {
                            id: subtitleText
                            Layout.fillWidth: true
                            visible: root.subtitle.length > 0
                            text: root.subtitle
                            color: Common.Config.color.on_surface_variant
                            opacity: 0.78
                            clip: true
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
                                duration: Common.Config.motion.duration.shortMs
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }

            Loader {
                id: detailLoader
                Layout.fillWidth: true
                active: root.expanded
                visible: active
                Layout.preferredHeight: active && item ? item.implicitHeight : 0
                sourceComponent: detailComponent
            }

            Component {
                id: detailComponent

                Rectangle {
                    width: detailLoader.width
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
                                id: sectionBlock
                                required property var modelData
                                readonly property string kind: root.sectionKind(modelData)
                                readonly property string previewText: root.sectionPreview(modelData)
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

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: Math.min(220, Math.max(42, detailText.contentHeight + 16))
                                    radius: Common.Config.shape.corner.xs
                                    color: Common.Config.color.surface
                                    border.width: 1
                                    border.color: Qt.alpha(Common.Config.color.on_surface, 0.07)

                                    Flickable {
                                        id: detailFlick
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        clip: true
                                        contentWidth: width
                                        contentHeight: detailText.contentHeight
                                        boundsBehavior: Flickable.StopAtBounds
                                        boundsMovement: Flickable.StopAtBounds
                                        flickableDirection: Flickable.VerticalFlick
                                        interactive: contentHeight > height

                                        TextEdit {
                                            id: detailText
                                            width: detailFlick.width
                                            text: sectionBlock.previewText
                                            textFormat: TextEdit.PlainText
                                            readOnly: true
                                            selectByMouse: true
                                            wrapMode: TextEdit.Wrap
                                            color: Common.Config.color.on_surface
                                            selectedTextColor: Common.Config.color.on_primary
                                            selectionColor: Common.Config.color.primary
                                            font.family: root.detailFontFamily(sectionBlock.kind)
                                            font.pixelSize: 11
                                        }
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
                    }
                }
            }
        }
    }
}
