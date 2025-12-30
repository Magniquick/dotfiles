pragma Singleton
import QtQml
import QtQuick

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
    readonly property real devicePixelRatio: (Qt.application && Qt.application.screens && Qt.application.screens.length > 0)
        ? Qt.application.screens[0].devicePixelRatio
        : 1
    readonly property int moduleMarginBottom: space.none
    readonly property int moduleMarginTop: 4 / root.devicePixelRatio
    readonly property int moduleMarginX: space.none
    readonly property int modulePaddingX: space.sm
    readonly property int modulePaddingY: space.none
    readonly property int moduleSpacing: space.xs
    readonly property QtObject motion: QtObject {
        readonly property QtObject distance: QtObject {
            readonly property int large: 12
            readonly property int medium: 8
            readonly property int small: 4
        }
        readonly property QtObject duration: QtObject {
            readonly property int extraLong: Math.round(360 * root.motionScale)
            readonly property int longMs: Math.round(240 * root.motionScale)
            readonly property int medium: Math.round(180 * root.motionScale)
            readonly property int pulse: Math.round(900 * root.motionScale)
            readonly property int shortMs: Math.round(140 * root.motionScale)
        }
        readonly property QtObject easing: QtObject {
            readonly property int emphasized: Easing.InOutCubic
            readonly property int standard: Easing.OutCubic
        }
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
    readonly property QtObject shape: QtObject {
        readonly property QtObject corner: QtObject {
            readonly property int lg: 16
            readonly property int md: 12
            readonly property int sm: 8
            readonly property int xl: 28
            readonly property int xs: 4
        }
    }
    readonly property QtObject space: QtObject {
        readonly property int lg: 16
        readonly property int md: 12
        readonly property int none: 0
        readonly property int sm: 8
        readonly property int xl: 20
        readonly property int xs: 4
        readonly property int xxl: 24
    }
    readonly property int spaceHalfXs: Math.max(1, Math.round(space.xs / 2))
    readonly property QtObject state: QtObject {
        readonly property real disabledOpacity: 0.5
        readonly property real hoverOpacity: 0.08
        readonly property real pressedOpacity: 0.18
    }
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
    readonly property QtObject type: QtObject {

        // Body - Long passages
        readonly property QtObject bodyLarge: QtObject {
            readonly property int line: 24
            readonly property int size: 16
            readonly property int weight: Font.Normal
        }
        readonly property QtObject bodyMedium: QtObject {
            readonly property int line: 20
            readonly property int size: 14
            readonly property int weight: Font.Normal
        }
        readonly property QtObject bodySmall: QtObject {
            readonly property int line: 16
            readonly property int size: 12
            readonly property int weight: Font.Normal
        }
        // Display - Largest text, expressive
        readonly property QtObject displayLarge: QtObject {
            readonly property int line: 64
            readonly property int size: 57
            readonly property int weight: Font.Normal
        }
        readonly property QtObject displayMedium: QtObject {
            readonly property int line: 52
            readonly property int size: 45
            readonly property int weight: Font.Normal
        }
        readonly property QtObject displaySmall: QtObject {
            readonly property int line: 44
            readonly property int size: 36
            readonly property int weight: Font.Normal
        }

        // Headline - Short, high-emphasis text
        readonly property QtObject headlineLarge: QtObject {
            readonly property int line: 40
            readonly property int size: 32
            readonly property int weight: Font.Normal
        }
        readonly property QtObject headlineMedium: QtObject {
            readonly property int line: 36
            readonly property int size: 28
            readonly property int weight: Font.Normal
        }
        readonly property QtObject headlineSmall: QtObject {
            readonly property int line: 32
            readonly property int size: 24
            readonly property int weight: Font.Normal
        }

        // Label - Small, utilitarian text
        readonly property QtObject labelLarge: QtObject {
            readonly property int line: 20
            readonly property int size: 14
            readonly property int weight: Font.Medium
        }
        readonly property QtObject labelMedium: QtObject {
            readonly property int line: 16
            readonly property int size: 12
            readonly property int weight: Font.Medium
        }
        readonly property QtObject labelSmall: QtObject {
            readonly property int line: 16
            readonly property int size: 11
            readonly property int weight: Font.Medium
        }

        // Title - Medium-emphasis, shorter text
        readonly property QtObject titleLarge: QtObject {
            readonly property int line: 28
            readonly property int size: 22
            readonly property int weight: Font.Normal
        }
        readonly property QtObject titleMedium: QtObject {
            readonly property int line: 24
            readonly property int size: 16
            readonly property int weight: Font.Medium
        }
        readonly property QtObject titleSmall: QtObject {
            readonly property int line: 20
            readonly property int size: 14
            readonly property int weight: Font.Medium
        }
    }
    readonly property color warn: m3.error
    readonly property int workspaceHeight: barHeight
    readonly property int workspacePaddingX: space.sm
    readonly property color yellow: m3.warning
}
