pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import Quickshell
import "../../common/materialkit" as MK
import "../../common" as Common

// Code block styled like metrics cards - subtle bg, thin border
MK.Card {
    id: root
    property string code: ""
    property string language: "txt"
    property bool editing: false
    property string selectionKey: ""
    property string activeSelectionKey: ""
    readonly property string displayCode: String(root.code || "").replace(/\n+$/, "")
    readonly property int lineCount: Math.max(1, root.displayCode.split("\n").length)

    signal codeEdited(string newCode)
    signal selectionActivated(string selectionKey)

    function clearSelection() {
        if (codeArea.selectedText.length > 0)
            codeArea.deselect();
    }

    onActiveSelectionKeyChanged: {
        if (activeSelectionKey !== selectionKey)
            clearSelection();
    }

    implicitHeight: codeColumn.implicitHeight
    type: MK.Enum.cardOutlined

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
                Layout.preferredWidth: 24
                Layout.preferredHeight: 20
                radius: 10
                color: copyBtn.copied ? Qt.alpha(Common.Config.color.tertiary, 0.15) : "transparent"

                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: copyBtn.copied ? "\udb80\udd91" : "\uf0c5"
                    color: copyBtn.copied ? Common.Config.color.tertiary : Common.Config.color.on_surface_variant
                    font.family: Common.Config.iconFontFamily
                    font.pixelSize: 10
                    opacity: copyBtn.copied ? 1 : 0.6
                }

                MK.HybridRipple {
                    anchors.fill: parent
                    color: Common.Config.color.on_surface
                    pressX: copyArea.pressX
                    pressY: copyArea.pressY
                    pressed: copyArea.pressed
                    radius: parent.radius
                    stateOpacity: copyArea.containsMouse ? Common.Config.state.hoverOpacity : 0
                }
                MouseArea {
                    id: copyArea
                    property real pressX: width / 2
                    property real pressY: height / 2
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.clipboardText = root.displayCode
                        copyBtn.copied = true
                        copyTimer.restart()
                    }
                    onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
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
                    model: root.lineCount
                    Text {
                        required property int index
                        width: 24
                        horizontalAlignment: Text.AlignRight
                        text: index + 1
                        color: Common.Config.color.on_surface_variant
                        font.family: codeArea.font.family
                        font.pixelSize: codeArea.font.pixelSize
                        opacity: 0.3
                    }
                }
            }

            // Separator line
            Rectangle {
                Layout.fillHeight: true
                Layout.rightMargin: Common.Config.space.sm
                Layout.preferredWidth: 1
                color: Qt.alpha(Common.Config.color.on_surface, 0.05)
            }

            // Code area
            Flickable {
                id: codeFlick
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                implicitHeight: Math.max(codeArea.contentHeight, codeContentItem.height)
                contentWidth: codeContentItem.width
                contentHeight: codeContentItem.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                boundsMovement: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalAndVerticalFlick

                Item {
                    id: codeContentItem
                    width: Math.max(codeArea.contentWidth, codeFlick.width)
                    height: codeArea.contentHeight

                    MK.TextEdit {
                        id: codeArea
                        anchors.left: parent.left
                        anchors.top: parent.top
                        width: parent.width
                        height: contentHeight
                        readOnly: !root.editing
                        selectByMouse: true
                        font.family: "JetBrainsMono NFP"
                        font.pixelSize: 12
                        color: Common.Config.color.on_surface
                        selectionColor: Qt.alpha(Common.Config.color.primary, 0.3)
                        selectedTextColor: Common.Config.color.on_surface
                        text: root.displayCode
                        wrapMode: TextEdit.NoWrap

                        onTextChanged: {
                            if (root.editing) root.codeEdited(text)
                        }

                        onSelectedTextChanged: {
                            if (selectedText.length > 0)
                                root.selectionActivated(root.selectionKey);
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
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                    function clampX(value) {
                        const maxX = Math.max(0, codeFlick.contentWidth - codeFlick.width);
                        return Math.max(0, Math.min(maxX, value));
                    }

                    onWheel: event => {
                        let deltaX = 0;

                        if (event.pixelDelta && event.pixelDelta.x !== 0) {
                            deltaX = event.pixelDelta.x;
                        } else if (event.angleDelta.x !== 0) {
                            deltaX = event.angleDelta.x / 2;
                        } else if (event.modifiers & Qt.ShiftModifier) {
                            deltaX = event.angleDelta.y / 2;
                        }

                        if (deltaX === 0)
                            return;

                        codeFlick.contentX = clampX(codeFlick.contentX - deltaX);
                        event.accepted = true;
                    }
                }

                T.ScrollBar.horizontal: MK.ScrollBar {
                    policy: T.ScrollBar.AsNeeded
                    height: 4
                    contentItem: Rectangle {
                        implicitHeight: 4
                        radius: 2
                        color: Qt.alpha(Common.Config.color.on_surface, 0.15)
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
