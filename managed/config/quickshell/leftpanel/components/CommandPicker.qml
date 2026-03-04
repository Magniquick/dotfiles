pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../common/materialkit" as MK
import "../../common" as Common

MK.Card {
    id: root

    property string command: ""
    property var options: []
    property bool showAllToggle: false

    signal optionSelected(string value)
    signal dismissed

    property string filterText: ""
    property bool showAll: false
    property var filteredOptions: []

    type: MK.Enum.cardOutlined

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
                color: "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "\uf00d" // nf-md-close
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
                    onClicked: root.dismissed()
                    onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
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

                    MK.TextField {
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
                        color: "transparent"
                        visible: root.filterText.length > 0

                        Text {
                            anchors.centerIn: parent
                            text: "\uf00d" // nf-md-close
                            color: Common.Config.color.on_surface_variant
                            font.family: Common.Config.iconFontFamily
                            font.pixelSize: 13
                        }

                        MK.HybridRipple {
                            anchors.fill: parent
                            color: Common.Config.color.on_surface
                            pressX: clearArea.pressX
                            pressY: clearArea.pressY
                            pressed: clearArea.pressed
                            radius: parent.radius
                            stateOpacity: clearArea.containsMouse ? Common.Config.state.hoverOpacity : 0
                        }
                        MouseArea {
                            id: clearArea
                            property real pressX: width / 2
                            property real pressY: height / 2
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.filterText = "";
                                filterInput.text = "";
                            }
                            onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
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

                MK.HybridRipple {
                    anchors.fill: parent
                    color: root.showAll ? Common.Config.color.on_primary : Common.Config.color.on_surface
                    pressX: toggleArea.pressX
                    pressY: toggleArea.pressY
                    pressed: toggleArea.pressed
                    radius: parent.radius
                    stateOpacity: toggleArea.containsMouse ? Common.Config.state.hoverOpacity : 0
                }
                MouseArea {
                    id: toggleArea
                    property real pressX: width / 2
                    property real pressY: height / 2
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showAll = !root.showAll
                    onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
                }
            }
        }

        // Options list
        MK.ListView {
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
                    property real pressX: width / 2
                    property real pressY: height / 2
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.optionSelected(optionItem.modelData.value)
                    onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
                }

                MK.HybridRipple {
                    anchors.fill: parent
                    color: Common.Config.color.on_surface
                    pressX: optionArea.pressX
                    pressY: optionArea.pressY
                    pressed: optionArea.pressed
                    radius: parent.radius
                    stateOpacity: 0
                }
            }
        }
    }
}
