pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../common/materialkit" as MK
import "../../common" as Common

MK.Card {
    id: root

    property string errorText: ""
    property bool busy: false

    signal submitted(string url, string label)
    signal dismissed

    type: MK.Enum.cardOutlined
    width: 360
    height: Math.min(420, contentColumn.implicitHeight + Common.Config.space.xl * 2)

    function focusPrimaryField() {
        urlInput.forceActiveFocus();
    }

    function clearForm() {
        urlInput.text = "";
        labelInput.text = "";
        root.errorText = "";
    }

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: Common.Config.space.lg
        spacing: Common.Config.space.md

        RowLayout {
            Layout.fillWidth: true
            spacing: Common.Config.space.sm

            Text {
                text: "\uf8fe"
                color: Common.Config.color.primary
                font.family: Common.Config.iconFontFamily
                font.pixelSize: 18
            }

            Text {
                text: "ADD MCP SERVER"
                color: Common.Config.color.primary
                font.family: Common.Config.fontFamily
                font.pixelSize: 12
                font.weight: Font.Black
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 13
                color: "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "\uf00d"
                    color: closeArea.containsMouse ? Common.Config.color.error : Common.Config.color.on_surface_variant
                    font.family: Common.Config.iconFontFamily
                    font.pixelSize: 14
                }

                MK.HybridRipple {
                    anchors.fill: parent
                    color: Common.Config.color.error
                    pressX: closeArea.pressX
                    pressY: closeArea.pressY
                    pressed: closeArea.pressed
                    radius: parent.radius
                    stateOpacity: closeArea.containsMouse ? Common.Config.state.hoverOpacity : 0
                }

                MouseArea {
                    id: closeArea
                    property real pressX: width / 2
                    property real pressY: height / 2
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !root.busy
                    onClicked: root.dismissed()
                    onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Add a new HTTP MCP endpoint. URL is required. Label is optional. Tokens and custom headers can be added later in mcp_servers.json."
            color: Common.Config.color.on_surface_variant
            font.family: Common.Config.fontFamily
            font.pixelSize: Common.Config.type.bodySmall.size
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Common.Config.space.xs

            Text {
                text: "Endpoint URL"
                color: Common.Config.color.on_surface
                font.family: Common.Config.fontFamily
                font.pixelSize: Common.Config.type.labelMedium.size
                font.weight: Font.DemiBold
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                radius: Common.Config.shape.corner.md
                color: Common.Config.color.surface
                border.width: 1
                border.color: Qt.alpha(Common.Config.color.on_surface, 0.12)

                MK.TextField {
                    id: urlInput
                    anchors.fill: parent
                    anchors.leftMargin: Common.Config.space.md
                    anchors.rightMargin: Common.Config.space.md
                    placeholderText: "https://example.com/mcp"
                    background: null
                    color: Common.Config.color.on_surface
                    placeholderTextColor: Qt.alpha(Common.Config.color.on_surface_variant, 0.7)
                    font.family: Common.Config.fontFamily
                    font.pixelSize: 13
                    enabled: !root.busy
                    selectByMouse: true
                    onTextEdited: root.errorText = ""
                    Keys.onReturnPressed: root.submitted(text, labelInput.text)
                    Keys.onEnterPressed: root.submitted(text, labelInput.text)
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Common.Config.space.xs

            Text {
                text: "Label (optional)"
                color: Common.Config.color.on_surface
                font.family: Common.Config.fontFamily
                font.pixelSize: Common.Config.type.labelMedium.size
                font.weight: Font.DemiBold
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                radius: Common.Config.shape.corner.md
                color: Common.Config.color.surface
                border.width: 1
                border.color: Qt.alpha(Common.Config.color.on_surface, 0.12)

                MK.TextField {
                    id: labelInput
                    anchors.fill: parent
                    anchors.leftMargin: Common.Config.space.md
                    anchors.rightMargin: Common.Config.space.md
                    placeholderText: "Optional display label"
                    background: null
                    color: Common.Config.color.on_surface
                    placeholderTextColor: Qt.alpha(Common.Config.color.on_surface_variant, 0.7)
                    font.family: Common.Config.fontFamily
                    font.pixelSize: 13
                    enabled: !root.busy
                    selectByMouse: true
                    onTextEdited: root.errorText = ""
                    Keys.onReturnPressed: root.submitted(urlInput.text, text)
                    Keys.onEnterPressed: root.submitted(urlInput.text, text)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.errorText.length > 0
            radius: Common.Config.shape.corner.md
            color: Qt.alpha(Common.Config.color.error, 0.12)
            border.width: 1
            border.color: Qt.alpha(Common.Config.color.error, 0.25)
            implicitHeight: errorLabel.implicitHeight + Common.Config.space.md * 2

            Text {
                id: errorLabel
                anchors.fill: parent
                anchors.margins: Common.Config.space.md
                wrapMode: Text.WordWrap
                text: root.errorText
                color: Common.Config.color.error
                font.family: Common.Config.fontFamily
                font.pixelSize: Common.Config.type.bodySmall.size
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: Common.Config.space.sm

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: Common.Config.shape.corner.md
                color: Common.Config.color.surface
                border.width: 1
                border.color: Qt.alpha(Common.Config.color.on_surface, 0.14)

                Text {
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Common.Config.color.on_surface_variant
                    font.family: Common.Config.fontFamily
                    font.pixelSize: Common.Config.type.labelLarge.size
                    font.weight: Font.DemiBold
                }

                MK.HybridRipple {
                    anchors.fill: parent
                    color: Common.Config.color.on_surface
                    pressX: cancelArea.pressX
                    pressY: cancelArea.pressY
                    pressed: cancelArea.pressed
                    radius: parent.radius
                    stateOpacity: cancelArea.containsMouse ? Common.Config.state.hoverOpacity : 0
                }

                MouseArea {
                    id: cancelArea
                    property real pressX: width / 2
                    property real pressY: height / 2
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !root.busy
                    onClicked: root.dismissed()
                    onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: Common.Config.shape.corner.md
                color: root.busy ? Qt.alpha(Common.Config.color.primary, 0.5) : Common.Config.color.primary

                Text {
                    anchors.centerIn: parent
                    text: root.busy ? "Saving..." : "Add Server"
                    color: Common.Config.color.on_primary
                    font.family: Common.Config.fontFamily
                    font.pixelSize: Common.Config.type.labelLarge.size
                    font.weight: Font.Black
                }

                MK.HybridRipple {
                    anchors.fill: parent
                    color: Common.Config.color.on_primary
                    pressX: submitArea.pressX
                    pressY: submitArea.pressY
                    pressed: submitArea.pressed
                    radius: parent.radius
                    stateOpacity: submitArea.containsMouse && !root.busy ? Common.Config.state.hoverOpacity : 0
                }

                MouseArea {
                    id: submitArea
                    property real pressX: width / 2
                    property real pressY: height / 2
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
                    enabled: !root.busy
                    onClicked: root.submitted(urlInput.text, labelInput.text)
                    onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
                }
            }
        }
    }
}
