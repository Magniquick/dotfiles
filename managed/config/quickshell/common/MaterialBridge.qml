pragma Singleton

import QtQuick
import "materialkit" as MK
import "."

QtObject {
    id: root

    readonly property var colors: Colors.color
    readonly property string textFamily: "Google Sans"
    readonly property string iconFamily: "JetBrainsMono NFP"

    function applyTheme() {
        if (!MK.Token || !MK.Token.color)
            return;

        // Keep Quickshell palette authority with matugen by pinning accent to matugen primary.
        MK.Token.color.useSysColorSM = false;
        MK.Token.color.useSysAccentColor = false;
        MK.Token.color.accentColor = root.colors.primary;
    }

    function applyFonts() {
        if (!MK.Token || !MK.Token.font)
            return;

        if (root.textFamily && root.textFamily.length > 0)
            MK.Token.font.default_font.family = root.textFamily;
        if (root.iconFamily && root.iconFamily.length > 0) {
            MK.Token.font.icon_family = root.iconFamily;
            MK.Token.font.icon_fill_family = root.iconFamily;
        }
    }

    function sync() {
        applyTheme();
        applyFonts();
    }

    Component.onCompleted: sync()

    property var colorsChangedConnection: Connections {
        target: Colors
        function onColorChanged() {
            root.applyTheme();
        }
    }
}
