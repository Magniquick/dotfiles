pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../common" as Common

Rectangle {
    id: root

    property string command: ""
    property var options: []
    property bool showAllToggle: false

    signal optionSelected(string value)
    signal dismissed

    property string filterText: ""
    property bool showAll: false
    property var filteredOptions: []

    color: Common.Config.color.surface_dim
    radius: Common.Config.shape.corner.xl
    border.width: 2
    border.color: Common.Config.color.primary

    width: 320
    height: Math.min(
        560,
        headerRow.height
            + filterRow.height
            + optionsList.contentHeight
            + Common.Config.space.lg * 3
            + Common.Config.space.md
    )

    // Eat clicks inside the picker so the overlay "click outside to dismiss" area doesn't
    // accidentally close the picker when interacting with non-MouseArea controls like TextField.
    // NOTE: We intentionally do not place a full-surface MouseArea here, because that would
    // steal input from TextField and make filter/search feel "unclickable".

    function recompute() {
        const raw = root.options || [];
        const q = (root.filterText || "").trim().toLowerCase();

        let list = raw;

        if (root.showAllToggle && !root.showAll) {
            const rec = raw.filter(o => (o && o.recommended) === true);
            list = rec.length ? rec : raw;
        }

        if (q.length > 0) {
            list = list.filter(o => {
                const label = ((o && o.label) || "").toLowerCase();
                const value = ((o && o.value) || "").toLowerCase();
                const desc = ((o && o.description) || "").toLowerCase();
                return label.includes(q) || value.includes(q) || desc.includes(q);
            });
        }

        root.filteredOptions = list;
    }

    onOptionsChanged: root.recompute()
    onFilterTextChanged: root.recompute()
    onShowAllChanged: root.recompute()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Common.Config.space.lg
        spacing: Common.Config.space.md

        // Header
        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            spacing: Common.Config.space.sm

            Text {
                text: "\uf120" // nf-md-console
                color: Common.Config.color.primary
                font.family: Common.Config.iconFontFamily
                font.pixelSize: 18
            }

            Text {
                text: root.command.toUpperCase()
                color: Common.Config.color.primary
                font.family: Common.Config.fontFamily
                font.pixelSize: 12
                font.weight: Font.Black
            }

            Item {
                Layout.fillWidth: true
            }

            Rectangle {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                implicitWidth: 24
                implicitHeight: 24
                radius: 12
                color: closeArea.containsMouse ? Qt.alpha(Common.Config.color.error, 0.2) : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "\uf00d" // nf-md-close
                    color: closeArea.containsMouse ? Common.Config.color.error : Common.Config.color.on_surface_variant
                    font.family: Common.Config.iconFontFamily
                    font.pixelSize: 14
                }

                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dismissed()
                }
            }
        }

        RowLayout {
            id: filterRow
            Layout.fillWidth: true
            spacing: Common.Config.space.sm

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                radius: Common.Config.shape.corner.md
                color: Common.Config.color.surface
                border.width: 1
                border.color: Qt.alpha(Common.Config.color.on_surface, 0.12)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Common.Config.space.md
                    anchors.rightMargin: Common.Config.space.sm
                    spacing: Common.Config.space.sm

                    Text {
                        text: "\uf349" // nf-md-magnify
                        color: Common.Config.color.on_surface_variant
                        font.family: Common.Config.iconFontFamily
                        font.pixelSize: 14
                        opacity: 0.8
                        Layout.alignment: Qt.AlignVCenter
                    }

                    TextField {
                        id: filterInput
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: root.filterText
                        placeholderText: "Filter..."
                        background: null
                        padding: 0
                        color: Common.Config.color.on_surface
                        placeholderTextColor: Qt.alpha(Common.Config.color.on_surface_variant, 0.7)
                        font.family: Common.Config.fontFamily
                        font.pixelSize: 12
                        selectByMouse: true

                        onTextEdited: root.filterText = text
                    }

                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 12
                        color: clearArea.containsMouse ? Qt.alpha(Common.Config.color.on_surface, 0.08) : "transparent"
                        visible: root.filterText.length > 0

                        Text {
                            anchors.centerIn: parent
                            text: "\uf00d" // nf-md-close
                            color: Common.Config.color.on_surface_variant
                            font.family: Common.Config.iconFontFamily
                            font.pixelSize: 13
                        }

                        MouseArea {
                            id: clearArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.filterText = "";
                                filterInput.text = "";
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 54
                Layout.preferredHeight: 34
                radius: Common.Config.shape.corner.md
                visible: root.showAllToggle
                color: root.showAll ? Common.Config.color.primary : Common.Config.color.surface
                border.width: 1
                border.color: root.showAll ? Common.Config.color.primary : Qt.alpha(Common.Config.color.on_surface, 0.12)

                Text {
                    anchors.centerIn: parent
                    text: root.showAll ? "ALL" : "REC"
                    color: root.showAll ? Common.Config.color.on_primary : Common.Config.color.on_surface_variant
                    font.family: Common.Config.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showAll = !root.showAll
                }
            }
        }

        // Options list
        ListView {
            id: optionsList
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Common.Config.space.xs
            clip: true
            model: root.filteredOptions

            delegate: Rectangle {
                id: optionItem
                required property int index
                required property var modelData

                readonly property color itemAccent: optionItem.modelData.accent || Common.Config.color.primary

                width: optionsList.width
                height: 56
                radius: Common.Config.shape.corner.md
                color: optionArea.containsMouse ? optionItem.itemAccent : Common.Config.color.surface
                border.width: 1
                border.color: optionArea.containsMouse ? optionItem.itemAccent : Qt.alpha(optionItem.itemAccent, 0.3)

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
                Behavior on border.color {
                    ColorAnimation {
                        duration: 150
                    }
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: Common.Config.space.md
                    spacing: Common.Config.space.md

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        sourceSize: Qt.size(36, 36)
                        source: optionItem.modelData.iconImage ? Qt.resolvedUrl("../" + optionItem.modelData.iconImage) : ""
                        visible: !!optionItem.modelData.iconImage
                        fillMode: Image.PreserveAspectFit
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: optionItem.modelData.icon || "\uf101"
                        color: optionArea.containsMouse ? Common.Config.color.on_primary : optionItem.itemAccent
                        font.family: Common.Config.iconFontFamily
                        font.pixelSize: 18
                        visible: !optionItem.modelData.iconImage

                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: optionItem.modelData.label || ""
                            color: optionArea.containsMouse ? Common.Config.color.on_primary : optionItem.itemAccent
                            font.family: Common.Config.fontFamily
                            font.pixelSize: Common.Config.type.bodyMedium.size
                            font.weight: Font.Medium

                            Behavior on color {
                                ColorAnimation {
                                    duration: 150
                                }
                            }
                        }

                        Text {
                            text: optionItem.modelData.description || ""
                            color: optionArea.containsMouse ? Qt.alpha(Common.Config.color.on_primary, 0.7) : Common.Config.color.on_surface_variant
                            font.family: Common.Config.fontFamily
                            font.pixelSize: Common.Config.type.bodySmall.size
                            visible: (optionItem.modelData.description || "").length > 0

                            Behavior on color {
                                ColorAnimation {
                                    duration: 150
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    id: optionArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.optionSelected(optionItem.modelData.value)
                }
            }
        }
    }
}
