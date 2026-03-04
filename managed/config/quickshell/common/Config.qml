pragma Singleton
import QtQml
import QtQuick
import Quickshell
import "."

QtObject {
    id: root

    readonly property color barBackground: "transparent"
    readonly property color barModuleBackground: Qt.alpha(color.surface_container, 0.95)
    readonly property int barModuleBorderWidth: 1
    // Use a fixed tonal step to avoid drift: richer than surface, calmer than saturated accents.
    readonly property color barPopupSurface: blendOklab(color.surface_container_lowest, color.surface_tint, 0.1)
    readonly property int barHeight: 32
    readonly property int barPadding: space.none
    readonly property bool barPillShadowsEnabled: true
    readonly property bool enablePrivacyModule: true
    readonly property string fontFamily: "Google Sans"
    readonly property int fontSize: type.bodyMedium.size
    readonly property int groupEdgeMargin: space.sm
    readonly property int groupMarginX: space.none
    readonly property int groupModuleSpacing: space.none
    readonly property int groupPaddingX: space.xs
    readonly property string iconFontFamily: "JetBrainsMono NFP"
    readonly property int iconSize: type.bodyMedium.size
    readonly property string loginShell: {
        const shellValue = Quickshell.env("SHELL");
        return shellValue && shellValue !== "" ? shellValue : "sh";
    }
    // Centralized secrets/config env file. Used by multiple shells/modules.
    readonly property string envFile: Quickshell.shellPath("common/.env")
    readonly property var color: Colors.color
    readonly property var palette: Colors.palette
    // Mixed-DPI note: avoid a global DPR derived from `Quickshell.screens[0]`.
    // Use `QsWindow.devicePixelRatio` (per-window) or `ShellScreen.devicePixelRatio` (per-screen)
    // at the point of use instead.
    readonly property int moduleMarginBottom: space.none
    readonly property int outerGaps: 4
    readonly property int moduleMarginX: space.none
    readonly property int modulePaddingX: space.sm
    readonly property int modulePaddingY: space.none
    readonly property int moduleSpacing: space.xs
    readonly property Motion motion: Motion {
        motionScale: root.motionScale
    }
    readonly property real motionScale: reducedMotion ? 0.6 : 1
    readonly property bool reducedMotion: false
    readonly property int sectionSpacing: space.xs
    readonly property Shape shape: Shape {}
    readonly property Slider slider: Slider {}
    readonly property Space space: Space {}
    readonly property int spaceHalfXs: Math.max(1, Math.round(space.xs / 2))
    readonly property State state: State {}
    readonly property int tooltipBorderWidth: 1
    readonly property int tooltipOffset: space.sm
    readonly property int tooltipPadding: space.md
    readonly property bool tooltipPulseAnimationEnabled: false
    readonly property int tooltipRadius: shape.corner.md
    readonly property TypeScale type: TypeScale {}
    readonly property color urlColor: color.primary
    readonly property int workspaceDragDwellMs: 300
    readonly property int workspaceHeight: barHeight
    readonly property int workspacePaddingX: space.sm

    function _clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }

    function _cbrt(value) {
        if (value === 0)
            return 0;
        return value < 0 ? -Math.pow(-value, 1 / 3) : Math.pow(value, 1 / 3);
    }

    function _srgbToLinear(value) {
        return value <= 0.04045 ? (value / 12.92) : Math.pow((value + 0.055) / 1.055, 2.4);
    }

    function _linearToSrgb(value) {
        return value <= 0.0031308 ? (12.92 * value) : (1.055 * Math.pow(value, 1 / 2.4) - 0.055);
    }

    function _rgbToOklab(r, g, b) {
        const lr = _srgbToLinear(_clamp01(r));
        const lg = _srgbToLinear(_clamp01(g));
        const lb = _srgbToLinear(_clamp01(b));

        const l = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb;
        const m = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb;
        const s = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb;

        const lRoot = _cbrt(l);
        const mRoot = _cbrt(m);
        const sRoot = _cbrt(s);

        return {
            "L": 0.2104542553 * lRoot + 0.7936177850 * mRoot - 0.0040720468 * sRoot,
            "a": 1.9779984951 * lRoot - 2.4285922050 * mRoot + 0.4505937099 * sRoot,
            "b": 0.0259040371 * lRoot + 0.7827717662 * mRoot - 0.8086757660 * sRoot
        };
    }

    function _oklabToRgb(L, a, b) {
        const lRoot = L + 0.3963377774 * a + 0.2158037573 * b;
        const mRoot = L - 0.1055613458 * a - 0.0638541728 * b;
        const sRoot = L - 0.0894841775 * a - 1.2914855480 * b;

        const l = lRoot * lRoot * lRoot;
        const m = mRoot * mRoot * mRoot;
        const s = sRoot * sRoot * sRoot;

        const lr = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
        const lg = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
        const lb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;

        return {
            "r": _clamp01(_linearToSrgb(lr)),
            "g": _clamp01(_linearToSrgb(lg)),
            "b": _clamp01(_linearToSrgb(lb))
        };
    }

    function blendOklab(fromColor, toColor, t) {
        const mix = _clamp01(t);
        const fromLab = _rgbToOklab(fromColor.r, fromColor.g, fromColor.b);
        const toLab = _rgbToOklab(toColor.r, toColor.g, toColor.b);

        const L = fromLab.L + (toLab.L - fromLab.L) * mix;
        const A = fromLab.a + (toLab.a - fromLab.a) * mix;
        const B = fromLab.b + (toLab.b - fromLab.b) * mix;
        const rgb = _oklabToRgb(L, A, B);
        const alpha = fromColor.a + (toColor.a - fromColor.a) * mix;

        return Qt.rgba(rgb.r, rgb.g, rgb.b, _clamp01(alpha));
    }

    function adjustOklabLightness(colorValue, factor) {
        const safeFactor = Math.max(0, factor);
        const lab = _rgbToOklab(colorValue.r, colorValue.g, colorValue.b);
        const rgb = _oklabToRgb(_clamp01(lab.L * safeFactor), lab.a, lab.b);
        return Qt.rgba(rgb.r, rgb.g, rgb.b, _clamp01(colorValue.a));
    }
}
