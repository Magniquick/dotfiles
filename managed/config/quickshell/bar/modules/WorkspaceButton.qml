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
import "../components"
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T

T.Button {
    id: root

    property bool active: false
    property string dispatchName: ""
    property string fontFamily: Config.fontFamily
    property int fontSize: Config.fontSize
    property var hypr
    property string label: ""
    property int paddingX: Config.workspacePaddingX
    readonly property int uniformTextWidth: metrics.advanceWidth("10")
    property bool uniformWidth: true
    property bool urgent: false
    property var workspace
    property int longPressMs: 450
    property int dragDwellMs: Config.workspaceDragDwellMs
    property bool _longPressFired: false
    readonly property bool wsHovered: hoverHandler.hovered

    signal longPressed()

    Layout.alignment: Qt.AlignVCenter
    hoverEnabled: true
    padding: 0
    implicitHeight: Config.workspaceHeight
    implicitWidth: (root.uniformWidth ? Math.max(labelText.implicitWidth, root.uniformTextWidth) : labelText.implicitWidth) + root.paddingX * 2

    onPressedChanged: {
        if (root.pressed) {
            root._longPressFired = false;
            longPressTimer.restart();
        } else {
            longPressTimer.stop();
        }
    }
    onClicked: {
        // If the press already triggered a long-press action, suppress the click.
        if (root._longPressFired)
            return;

        if (root.workspace && root.workspace.activate)
            root.workspace.activate();
        else if (root.hypr && root.dispatchName)
            root.hypr.dispatch("workspace " + root.dispatchName);
    }

    FontMetrics {
        id: metrics

        font.family: root.fontFamily
        font.pixelSize: root.fontSize
    }

    HoverHandler {
        id: hoverHandler
    }

    Timer {
        id: longPressTimer
        interval: root.longPressMs
        repeat: false
        onTriggered: {
            if (!root.pressed)
                return;
            root._longPressFired = true;
            root.longPressed();
        }
    }

    DropArea {
        anchors.fill: parent
        onEntered: dragDwellTimer.restart()
        onExited: dragDwellTimer.stop()
    }

    Timer {
        id: dragDwellTimer
        interval: root.dragDwellMs
        repeat: false
        onTriggered: {
            if (root.workspace && root.workspace.activate)
                root.workspace.activate();
            else if (root.hypr && root.dispatchName)
                root.hypr.dispatch("workspace " + root.dispatchName);
        }
    }

    contentItem: Text {
        id: labelText

        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        text: root.label
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        font.bold: root.active
        color: root.urgent ? Config.color.secondary : (root.active ? Config.color.primary : Config.color.on_surface_variant)
    }

    background: Rectangle {
        radius: height / 2
        antialiasing: true

        // Use our own hover tracking; QtQuick.Templates' hovered handling can vary by style.
        color: root.active ? Config.color.surface_variant : (root.wsHovered ? Config.color.surface_container_high : "transparent")
        // Avoid any "almost transparent" rendering artifacts by not drawing at all when idle.
        visible: root.active || root.wsHovered || root.pressed

        HybridRipple {
            anchors.fill: parent
            radius: parent.radius
            pressX: root.pressX
            pressY: root.pressY
            pressed: root.pressed

            // Keep the ripple subtle and on-brand with the bar palette.
            // 0 when idle, otherwise you get a constant tint on inactive workspaces.
            stateOpacity: root.pressed ? 0.18 : (root.wsHovered ? 0.10 : 0)
            color: root.active ? Config.color.primary : Config.color.on_surface_variant
        }
    }
}
