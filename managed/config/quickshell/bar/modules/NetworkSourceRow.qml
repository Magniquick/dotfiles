pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".." as Bar
import "../../common/materialkit" as MK

Rectangle {
    id: root

    required property var modelData
    required property var moduleRoot
    required property int rowHeight

    readonly property bool active: !!modelData && !!modelData.active
    readonly property string sourceName: modelData ? String(modelData.name || "") : ""
    readonly property string sourceType: modelData ? String(modelData.type || "") : ""
    readonly property string sourceDevice: modelData ? String(modelData.device || "") : ""
    readonly property bool connectable: modelData ? !!modelData.connectable : false
    readonly property bool switching: moduleRoot.sourceSwitching && moduleRoot.sourceSwitchingName === root.sourceName

    Layout.fillWidth: true
    Layout.preferredHeight: rowHeight
    radius: Bar.Config.shape.corner.md
    color: rowMouseArea.containsMouse
        ? Qt.alpha(Bar.Config.color.surface_variant, 0.45)
        : (active ? Qt.alpha(Bar.Config.color.primary_container, 0.45) : Bar.Config.color.surface_container_high)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Bar.Config.space.sm
        anchors.rightMargin: Bar.Config.space.sm
        spacing: Bar.Config.space.sm

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: 28
            Layout.preferredWidth: 28
            color: root.active ? Qt.alpha(Bar.Config.color.primary, 0.7) : Bar.Config.color.surface_variant
            radius: width / 2

            Text {
                anchors.centerIn: parent
                color: root.active ? Bar.Config.color.on_primary : Bar.Config.color.on_surface
                font.family: Bar.Config.iconFontFamily
                font.pixelSize: Bar.Config.type.labelLarge.size
                text: root.moduleRoot.sourceIcon(root.sourceType)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Bar.Config.space.none

            Text {
                Layout.fillWidth: true
                color: root.active ? Bar.Config.color.on_primary_container : Bar.Config.color.on_surface
                elide: Text.ElideRight
                font.family: Bar.Config.fontFamily
                font.pixelSize: Bar.Config.type.bodyLarge.size
                font.weight: Bar.Config.type.bodyLarge.weight
                text: root.sourceName !== "" ? root.sourceName : root.moduleRoot.sourceTypeLabel(root.sourceType)
            }
            Text {
                Layout.fillWidth: true
                color: Bar.Config.color.on_surface_variant
                elide: Text.ElideRight
                font.family: Bar.Config.fontFamily
                font.pixelSize: Bar.Config.type.labelMedium.size
                text: root.sourceDevice !== "" ? (root.moduleRoot.sourceTypeLabel(root.sourceType) + " • " + root.sourceDevice) : root.moduleRoot.sourceTypeLabel(root.sourceType)
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: activeLabel.implicitHeight + Bar.Config.spaceHalfXs
            Layout.preferredWidth: activeLabel.implicitWidth + Bar.Config.space.sm
            color: root.switching ? Qt.alpha(Bar.Config.color.secondary, 0.95) : Qt.alpha(Bar.Config.color.tertiary, 0.9)
            radius: Bar.Config.shape.corner.sm
            visible: root.switching

            Text {
                id: activeLabel

                anchors.centerIn: parent
                color: root.switching ? Bar.Config.color.on_secondary : Bar.Config.color.on_tertiary
                font.family: Bar.Config.fontFamily
                font.pixelSize: Bar.Config.type.labelSmall.size
                font.weight: Font.Bold
                text: "SWITCHING"
            }
        }
    }

    MK.HybridRipple {
        anchors.fill: parent
        color: root.active ? Bar.Config.color.on_primary_container : Bar.Config.color.on_surface
        pressX: rowMouseArea.pressX
        pressY: rowMouseArea.pressY
        pressed: rowMouseArea.pressed
        radius: parent.radius
        stateLayerEnabled: false
        stateOpacity: 0
    }

    MouseArea {
        id: rowMouseArea

        property real pressX: width / 2
        property real pressY: height / 2

        anchors.fill: parent
        enabled: root.connectable && !root.active && !root.moduleRoot.sourceSwitching
        hoverEnabled: true
        onClicked: function() {
            Bar.NetworkService.switchSource(root.modelData);
        }
        onPressed: function(mouse) {
            pressX = mouse.x;
            pressY = mouse.y;
        }
    }
}
