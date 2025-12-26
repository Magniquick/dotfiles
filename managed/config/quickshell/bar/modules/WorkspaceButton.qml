import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

Rectangle {
    id: root

    property var workspace
    property var hyprland
    property string label: ""
    property string dispatchName: ""
    property bool active: false
    property bool urgent: false
    property bool hovered: false
    property int paddingX: Config.workspacePaddingX
    property string fontFamily: Config.fontFamily
    property int fontSize: Config.fontSize
    property bool uniformWidth: true
    readonly property int uniformTextWidth: metrics.advanceWidth("10")

    color: root.active ? Config.moduleBackgroundMuted : (root.hovered ? Config.moduleBackgroundHover : "transparent")
    radius: height / 2
    antialiasing: true
    implicitHeight: Config.workspaceHeight
    implicitWidth: (root.uniformWidth ? Math.max(labelText.implicitWidth, root.uniformTextWidth) : labelText.implicitWidth) + root.paddingX * 2
    Layout.alignment: Qt.AlignVCenter

    Text {
        id: labelText

        anchors.centerIn: parent
        text: root.label
        color: root.urgent ? Config.warn : (root.active ? Config.accent : Config.textMuted)
        horizontalAlignment: Text.AlignHCenter
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        font.bold: root.active
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
