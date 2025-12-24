import QtQml
import QtQuick
import "."

pragma Singleton

QtObject {
    id: root
    readonly property string fontFamily: "JetBrainsMono Nerd Font Propo"
    readonly property string iconFontFamily: fontFamily
    readonly property bool reducedMotion: false
    readonly property real motionScale: reducedMotion ? 0.6 : 1

    readonly property QtObject space: QtObject {
        readonly property int none: 0
        readonly property int xs: 4
        readonly property int sm: 8
        readonly property int md: 12
        readonly property int lg: 16
        readonly property int xl: 20
        readonly property int xxl: 24
    }

    readonly property QtObject shape: QtObject {
        readonly property QtObject corner: QtObject {
            readonly property int xs: 4
            readonly property int sm: 8
            readonly property int md: 12
            readonly property int lg: 16
            readonly property int xl: 28
        }
    }

    readonly property QtObject motion: QtObject {
        readonly property QtObject duration: QtObject {
            readonly property int shortMs: Math.round(140 * root.motionScale)
            readonly property int medium: Math.round(180 * root.motionScale)
            readonly property int longMs: Math.round(240 * root.motionScale)
            readonly property int extraLong: Math.round(360 * root.motionScale)
            readonly property int pulse: Math.round(900 * root.motionScale)
        }
        readonly property QtObject easing: QtObject {
            readonly property int standard: Easing.OutCubic
            readonly property int emphasized: Easing.InOutCubic
        }
        readonly property QtObject distance: QtObject {
            readonly property int small: 4
            readonly property int medium: 8
            readonly property int large: 12
        }
    }

    readonly property QtObject type: QtObject {
        readonly property QtObject titleMedium: QtObject {
            readonly property int size: 16
            readonly property int line: 22
            readonly property int weight: Font.DemiBold
        }
        readonly property QtObject titleSmall: QtObject {
            readonly property int size: 14
            readonly property int line: 20
            readonly property int weight: Font.DemiBold
        }
        readonly property QtObject bodyMedium: QtObject {
            readonly property int size: 14
            readonly property int line: 20
            readonly property int weight: Font.Normal
        }
        readonly property QtObject bodySmall: QtObject {
            readonly property int size: 12
            readonly property int line: 16
            readonly property int weight: Font.Normal
        }
        readonly property QtObject labelMedium: QtObject {
            readonly property int size: 12
            readonly property int line: 16
            readonly property int weight: Font.Medium
        }
        readonly property QtObject labelSmall: QtObject {
            readonly property int size: 11
            readonly property int line: 14
            readonly property int weight: Font.Medium
        }
    }

    readonly property QtObject color: QtObject {
        readonly property color primary: ColorPalette.palette.mauve
        readonly property color onPrimary: ColorPalette.palette.base
        readonly property color secondary: ColorPalette.palette.pink
        readonly property color onSecondary: ColorPalette.palette.base
        readonly property color tertiary: ColorPalette.palette.lavender
        readonly property color onTertiary: ColorPalette.palette.base
        readonly property color surface: ColorPalette.palette.base
        readonly property color surfaceVariant: ColorPalette.palette.surface1
        readonly property color surfaceContainer: ColorPalette.palette.surface0
        readonly property color surfaceContainerHigh: ColorPalette.palette.surface1
        readonly property color surfaceContainerHighest: ColorPalette.palette.surface2
        readonly property color onSurface: ColorPalette.palette.text
        readonly property color onSurfaceVariant: ColorPalette.palette.subtext0
        readonly property color outline: ColorPalette.palette.surface2
        readonly property color outlineStrong: ColorPalette.palette.pink
        readonly property color shadow: Qt.rgba(
                                            ColorPalette.palette.crust.r,
                                            ColorPalette.palette.crust.g,
                                            ColorPalette.palette.crust.b,
                                            0.28
                                            )
        readonly property color error: ColorPalette.palette.red
        readonly property color onError: ColorPalette.palette.base
        readonly property color warning: ColorPalette.palette.yellow
        readonly property color onWarning: ColorPalette.palette.base
        readonly property color success: ColorPalette.palette.green
        readonly property color onSuccess: ColorPalette.palette.base
        readonly property color info: ColorPalette.palette.blue
        readonly property color onInfo: ColorPalette.palette.base
    }

    readonly property QtObject state: QtObject {
        readonly property real hoverOpacity: 0.08
        readonly property real pressedOpacity: 0.18
        readonly property real disabledOpacity: 0.5
    }

    readonly property int fontSize: type.bodyMedium.size
    readonly property int iconSize: type.bodyMedium.size
    readonly property int barHeight: 32
    readonly property int barPadding: space.none
    readonly property int modulePaddingX: space.sm
    readonly property int modulePaddingY: space.none
    readonly property int workspacePaddingX: space.sm
    readonly property int workspaceHeight: barHeight
    readonly property int moduleMarginTop: space.xs
    readonly property int moduleMarginBottom: space.none
    readonly property int moduleMarginX: space.none
    readonly property int groupPaddingX: space.xs
    readonly property int groupMarginX: space.none
    readonly property int groupEdgeMargin: space.sm
    readonly property int moduleSpacing: space.xs
    readonly property int groupModuleSpacing: space.none
    readonly property int sectionSpacing: space.xs
    readonly property int tooltipPadding: space.md
    readonly property int tooltipRadius: shape.corner.md
    readonly property int tooltipBorderWidth: 1
    readonly property int tooltipOffset: space.sm
    readonly property bool enablePrivacyModule: true

    readonly property color barBackground: "transparent"
    readonly property color moduleBackground: color.surfaceContainer
    readonly property color moduleBackgroundMuted: color.surfaceVariant
    readonly property color moduleBackgroundHover: color.surfaceContainerHigh
    readonly property color tooltipBackground: color.surface
    readonly property color tooltipBorder: color.outlineStrong
    readonly property color textColor: ColorPalette.palette.text
    readonly property color textMuted: ColorPalette.palette.subtext1
    readonly property color accent: color.primary
    readonly property color warn: color.error
    readonly property color lavender: color.tertiary
    readonly property color pink: color.secondary
    readonly property color flamingo: ColorPalette.palette.flamingo
    readonly property color yellow: color.warning
    readonly property color green: color.success
    readonly property color red: color.error
}
