import "./Colors.js" as Colors
import QtQml
import Quickshell

pragma Singleton

Singleton {
    readonly property var palette: convertPalette(Colors.palette)

    function hex(hexValue) {
        const clean = hexValue.replace("#", "");
        const intVal = parseInt(clean, 16);
        const r = (intVal >> 16) & 255;
        const g = (intVal >> 8) & 255;
        const b = intVal & 255;
        return Qt.rgba(r / 255, g / 255, b / 255, 1);
    }

    function convertPalette(rawPalette) {
        const convertedPalette = {};
        for (const key in rawPalette) {
            if (!Object.prototype.hasOwnProperty.call(rawPalette, key))
                continue;

            convertedPalette[key] = hex(rawPalette[key]);
        }
        return convertedPalette;
    }
}
