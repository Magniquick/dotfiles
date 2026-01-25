/**
 * @module WorkspaceButton
 * @description Individual workspace button for WorkspacesModule
 *
 * Features:
 * - Active/inactive/urgent state styling
 * - Hover highlight
 * - Click to switch workspace
 * - Uniform width option for consistent layout
 *
 * Dependencies:
 * - Quickshell.Hyprland: Workspace dispatch
 */
import ".."
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property bool active: false
    property string dispatchName: ""
    property string fontFamily: Config.fontFamily
    property int fontSize: Config.fontSize
    property bool hovered: false
    property var hyprland
    property string label: ""
    property int paddingX: Config.workspacePaddingX
    readonly property int uniformTextWidth: metrics.advanceWidth("10")
    property bool uniformWidth: true
    property bool urgent: false
    property var workspace

    Layout.alignment: Qt.AlignVCenter
    antialiasing: true
    color: root.active ? Config.color.surface_variant : (root.hovered ? Config.color.surface_container_high : "transparent")
    implicitHeight: Config.workspaceHeight
    implicitWidth: (root.uniformWidth ? Math.max(labelText.implicitWidth, root.uniformTextWidth) : labelText.implicitWidth) + root.paddingX * 2
    radius: height / 2

    Text {
        id: labelText

        anchors.centerIn: parent
        color: root.urgent ? Config.color.secondary : (root.active ? Config.color.primary : Config.color.on_surface_variant)
        font.bold: root.active
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        horizontalAlignment: Text.AlignHCenter
        text: root.label
    }
    FontMetrics {
        id: metrics

        font.family: root.fontFamily
        font.pixelSize: root.fontSize
    }
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true

        onClicked: {
            if (root.workspace && root.workspace.activate)
                root.workspace.activate();
            else if (root.hyprland && root.dispatchName)
                root.hyprland.dispatch("workspace " + root.dispatchName);
        }
        onEntered: root.hovered = true
        onExited: root.hovered = false
    }
}
