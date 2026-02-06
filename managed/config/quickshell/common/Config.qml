pragma Singleton
import QtQml
import QtQuick
import Quickshell
import "."

QtObject {
    id: root

    readonly property color barBackground: "transparent"
    readonly property color barModuleBackground: Qt.alpha(color.surface_container, 0.95)
    readonly property color barModuleBorderColor: Qt.alpha(color.outline_variant, 0.6)
    readonly property int barModuleBorderWidth: 1
    readonly property color barPopupSurface: color.on_secondary_fixed
    readonly property color barPopupBorderColor: color.outline_variant
    readonly property int barHeight: 32
    readonly property int barPadding: space.none
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
    readonly property int workspaceHeight: barHeight
    readonly property int workspacePaddingX: space.sm
}
