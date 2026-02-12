pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import Quickshell
import Qcm.Material as MD
import "../../common" as Common

// Code block styled like metrics cards - subtle bg, thin border
MD.Card {
    id: root
    property string code: ""
    property string language: "txt"
    property bool editing: false

    signal codeEdited(string newCode)

    implicitHeight: codeColumn.implicitHeight
    type: MD.Enum.CardOutlined

    ColumnLayout {
        id: codeColumn
        anchors.fill: parent
        spacing: 0

        // Header row (like StatCard header)
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Common.Config.space.sm
            Layout.bottomMargin: 0
            spacing: Common.Config.space.sm

            // Language pill (like CircularGauge label pill)
            Rectangle {
                implicitWidth: langRow.implicitWidth + Common.Config.space.md * 2
                implicitHeight: 20
                radius: 10
                color: Qt.alpha(Common.Config.color.on_surface, 0.05)
                border.width: 1
                border.color: Qt.alpha(Common.Config.color.on_surface, 0.05)

                Row {
                    id: langRow
                    anchors.centerIn: parent
                    spacing: Common.Config.space.xs

                    Text {
                        text: "\uf121" // code icon
                        color: Common.Config.color.on_surface_variant
                        font.family: Common.Config.iconFontFamily
                        font.pixelSize: 9
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: root.language.toUpperCase() || "TXT"
                        color: Common.Config.color.on_surface_variant
                        font {
                            family: Common.Config.fontFamily
                            pixelSize: 9
                            weight: Font.Bold
                        }
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Copy button
            Rectangle {
                id: copyBtn
                property bool copied: false
                width: 24
                height: 20
                radius: 10
                color: copyArea.containsMouse ? Qt.alpha(Common.Config.color.on_surface, 0.08) :
                       copied ? Qt.alpha(Common.Config.color.tertiary, 0.15) : "transparent"

                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: copyBtn.copied ? "\udb80\udd91" : "\uf0c5"
                    color: copyBtn.copied ? Common.Config.color.tertiary : Common.Config.color.on_surface_variant
                    font.family: Common.Config.iconFontFamily
                    font.pixelSize: 10
                    opacity: copyBtn.copied ? 1 : 0.6
                }

                MouseArea {
                    id: copyArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.clipboardText = root.code
                        copyBtn.copied = true
                        copyTimer.restart()
                    }
                }

                Timer {
                    id: copyTimer
                    interval: 1500
                    onTriggered: copyBtn.copied = false
                }
            }
        }

        // Code content with line numbers
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Common.Config.space.sm
            Layout.topMargin: Common.Config.space.xs
            spacing: 0

            // Line numbers
            Column {
                id: lineCol
                Layout.alignment: Qt.AlignTop
                Layout.rightMargin: Common.Config.space.sm

                Repeater {
                    model: Math.max(1, root.code.split("\n").length)
                    Text {
                        required property int index
                        width: 24
                        height: 18
                        horizontalAlignment: Text.AlignRight
                        verticalAlignment: Text.AlignVCenter
                        text: index + 1
                        color: Common.Config.color.on_surface_variant
                        font.family: "JetBrainsMono NFP"
                        font.pixelSize: 12
                        opacity: 0.3
                    }
                }
            }

            // Separator line
            Rectangle {
                Layout.fillHeight: true
                Layout.rightMargin: Common.Config.space.sm
                width: 1
                color: Qt.alpha(Common.Config.color.on_surface, 0.05)
            }

            // Code area
            MD.Flickable {
                id: codeFlick
                Layout.fillWidth: true
                implicitHeight: codeArea.implicitHeight
                contentWidth: codeArea.implicitWidth
                contentHeight: codeArea.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                T.ScrollBar.horizontal: MD.ScrollBar {
                    policy: T.ScrollBar.AsNeeded
                    height: 4
                    contentItem: Rectangle {
                        implicitHeight: 4
                        radius: 2
                        color: Qt.alpha(Common.Config.color.on_surface, 0.15)
                    }
                }

                MD.TextEdit {
                    id: codeArea
                    width: Math.max(implicitWidth, codeFlick.width)
                    readOnly: !root.editing
                    selectByMouse: true
                    font.family: "JetBrainsMono NFP"
                    font.pixelSize: 12
                    color: Common.Config.color.on_surface
                    selectionColor: Qt.alpha(Common.Config.color.primary, 0.3)
                    selectedTextColor: Common.Config.color.on_surface
                    text: root.code
                    wrapMode: TextEdit.NoWrap

                    onTextChanged: {
                        if (root.editing) root.codeEdited(text)
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Tab) {
                            const cursor = codeArea.cursorPosition
                            codeArea.insert(cursor, "    ")
                            codeArea.cursorPosition = cursor + 4
                            event.accepted = true
                        }
                    }
                }

                // Syntax highlighter loader
                Loader {
                    id: highlighterLoader
                    active: true
                    source: "SyntaxHighlighterWrapper.qml"
                    onLoaded: {
                        item.targetTextEdit = codeArea
                        item.lang = root.language
                    }
                }
            }
        }
    }
}
