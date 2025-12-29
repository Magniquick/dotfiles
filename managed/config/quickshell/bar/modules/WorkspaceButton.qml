import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

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
    color: root.active ? Config.moduleBackgroundMuted : (root.hovered ? Config.moduleBackgroundHover : "transparent")
    implicitHeight: Config.workspaceHeight
    implicitWidth: (root.uniformWidth ? Math.max(labelText.implicitWidth, root.uniformTextWidth) : labelText.implicitWidth) + root.paddingX * 2
    radius: height / 2

    Text {
        id: labelText

        anchors.centerIn: parent
        color: root.urgent ? Config.warn : (root.active ? Config.accent : Config.textMuted)
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
