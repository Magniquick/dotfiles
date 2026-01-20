pragma Singleton
import QtQml
import QtQuick
import Quickshell
import "../common"

QtObject {
    id: root

    readonly property color accent: m3.primary
    readonly property color barBackground: "transparent"
    readonly property int barHeight: 32
    readonly property int barPadding: space.none
    readonly property bool enablePrivacyModule: true
    readonly property color error: m3.error
    readonly property color flamingo: ColorPalette.palette.flamingo
    readonly property string fontFamily: "Google Sans"
    readonly property int fontSize: type.bodyMedium.size
    readonly property color green: m3.success
    readonly property int groupEdgeMargin: space.sm
    readonly property int groupMarginX: space.none
    readonly property int groupModuleSpacing: space.none
    readonly property int groupPaddingX: space.xs
    readonly property string iconFontFamily: "JetBrainsMono NFP"
    readonly property int iconSize: type.bodyMedium.size
    readonly property color info: m3.info
    readonly property color lavender: m3.tertiary
    readonly property var m3: {
        return {
            "primary": ColorPalette.palette.mauve,
            "onPrimary": ColorPalette.palette.base,
            "secondary": ColorPalette.palette.pink,
            "onSecondary": ColorPalette.palette.base,
            "tertiary": ColorPalette.palette.lavender,
            "onTertiary": ColorPalette.palette.base,
            "flamingo": ColorPalette.palette.flamingo,
            "surface": ColorPalette.palette.base,
            "surfaceVariant": ColorPalette.palette.surface1,
            "surfaceContainer": ColorPalette.palette.base,
            "surfaceContainerHigh": ColorPalette.palette.surface1,
            "surfaceContainerHighest": ColorPalette.palette.surface2,
            "onSurface": ColorPalette.palette.text,
            "onSurfaceVariant": ColorPalette.palette.subtext0,
            "outline": ColorPalette.palette.surface2,
            "outlineStrong": ColorPalette.palette.pink,
            "shadow": Qt.alpha(ColorPalette.palette.crust, 0.28),
            "error": ColorPalette.palette.red,
            "onError": ColorPalette.palette.base,
            "warning": ColorPalette.palette.yellow,
            "onWarning": ColorPalette.palette.base,
            "success": ColorPalette.palette.green,
            "onSuccess": ColorPalette.palette.base,
            "info": ColorPalette.palette.blue,
            "onInfo": ColorPalette.palette.base
        };
    }
    readonly property color moduleBackground: m3.surfaceContainer
    readonly property color moduleBackgroundHover: m3.surfaceContainerHigh
    readonly property color moduleBackgroundMuted: m3.surfaceVariant
    readonly property real devicePixelRatio: (Quickshell.screens && Quickshell.screens.length > 0)
        ? Quickshell.screens[0].devicePixelRatio
        : 1
    readonly property int moduleMarginBottom: space.none
    readonly property int moduleMarginTop: 4 / root.devicePixelRatio
    readonly property int moduleMarginX: space.none
    readonly property int modulePaddingX: space.sm
    readonly property int modulePaddingY: space.none
    readonly property int moduleSpacing: space.xs
    readonly property Motion motion: Motion {
        motionScale: root.motionScale
    }
    readonly property real motionScale: reducedMotion ? 0.6 : 1
    readonly property color onError: m3.onError
    readonly property color onInfo: m3.onInfo
    readonly property color onPrimary: m3.onPrimary
    readonly property color onSurface: m3.onSurface
    readonly property color onSurfaceVariant: m3.onSurfaceVariant
    readonly property color outline: m3.outline
    readonly property color outlineStrong: m3.outlineStrong
    readonly property color pink: m3.secondary
    readonly property color primary: m3.primary
    readonly property color red: m3.error
    readonly property bool reducedMotion: false
    readonly property int sectionSpacing: space.xs
    readonly property Shape shape: Shape {}
    readonly property Slider slider: Slider {}
    readonly property Space space: Space {}
    readonly property int spaceHalfXs: Math.max(1, Math.round(space.xs / 2))
    readonly property QtObject state: QtObject {
        readonly property real disabledOpacity: 0.5
        readonly property real hoverOpacity: 0.08
        readonly property real pressedOpacity: 0.18
    }
    readonly property real disabledOpacity: 0.5
    readonly property real hoverOpacity: 0.08
    readonly property real pressedOpacity: 0.18
    readonly property color surface: m3.surface
    readonly property color surfaceContainer: m3.surfaceContainer
    readonly property color surfaceContainerHigh: m3.surfaceContainerHigh
    readonly property color surfaceContainerHighest: m3.surfaceContainerHighest
    readonly property color surfaceVariant: m3.surfaceVariant
    readonly property color textColor: ColorPalette.palette.text
    readonly property color textMuted: ColorPalette.palette.subtext1
    readonly property color tooltipBackground: m3.surface
    readonly property color tooltipBorder: m3.outlineStrong
    readonly property int tooltipBorderWidth: 1
    readonly property int tooltipOffset: space.sm
    readonly property int tooltipPadding: space.md
    readonly property bool tooltipPulseAnimationEnabled: false
    readonly property int tooltipRadius: shape.corner.md
    readonly property TypeScale type: TypeScale {}
    readonly property color warn: m3.error
    readonly property int workspaceHeight: barHeight
    readonly property int workspacePaddingX: space.sm
    readonly property color yellow: m3.warning
}
