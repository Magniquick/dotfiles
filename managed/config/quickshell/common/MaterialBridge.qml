pragma Singleton

import QtQuick
import Qcm.Material as MD
import "."

QtObject {
    id: root

    readonly property var colors: Colors.color
    readonly property string textFamily: "Google Sans"
    readonly property string iconFamily: "JetBrainsMono NFP"

    function applyTheme() {
        if (!MD.Token || !MD.Token.color)
            return;

        // Keep Quickshell palette authority with matugen by pinning accent to matugen primary.
        MD.Token.color.useSysColorSM = false;
        MD.Token.color.useSysAccentColor = false;
        MD.Token.color.accentColor = root.colors.primary;
    }

    function applyFonts() {
        if (!MD.Token || !MD.Token.font)
            return;

        if (root.textFamily && root.textFamily.length > 0)
            MD.Token.font.default_font.family = root.textFamily;
        if (root.iconFamily && root.iconFamily.length > 0) {
            MD.Token.font.icon_family = root.iconFamily;
            MD.Token.font.icon_fill_family = root.iconFamily;
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
