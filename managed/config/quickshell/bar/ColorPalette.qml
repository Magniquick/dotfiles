pragma Singleton
import "./Colors.js" as Colors
import QtQml
import Quickshell

Singleton {
    readonly property var palette: convertPalette(Colors.palette)

    function convertPalette(rawPalette) {
        const convertedPalette = {};
        for (const key in rawPalette) {
            if (!Object.prototype.hasOwnProperty.call(rawPalette, key))
                continue;

            convertedPalette[key] = hex(rawPalette[key]);
        }
        return convertedPalette;
    }
    function hex(hexValue) {
        const clean = hexValue.replace("#", "");
        return "#" + clean;
    }
}
