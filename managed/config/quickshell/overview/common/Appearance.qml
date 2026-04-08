pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "functions"
import "." as OverviewCommon
import "../../common" as MainCommon

Singleton {
    id: root

    property QtObject m3colors: QtObject {
        property color m3primary: MainCommon.Config.color.primary
        property color m3onPrimary: MainCommon.Config.color.on_primary
        property color m3primaryContainer: MainCommon.Config.color.primary_container
        property color m3onPrimaryContainer: MainCommon.Config.color.on_primary_container
        property color m3secondary: MainCommon.Config.color.secondary
        property color m3onSecondary: MainCommon.Config.color.on_secondary
        property color m3secondaryContainer: MainCommon.Config.color.secondary_container
        property color m3onSecondaryContainer: MainCommon.Config.color.on_secondary_container
        property color m3background: MainCommon.Config.color.background
        property color m3onBackground: MainCommon.Config.color.on_background
        property color m3surface: MainCommon.Config.color.surface
        property color m3surfaceContainerLow: MainCommon.Config.color.surface_container_low
        property color m3surfaceContainer: MainCommon.Config.color.surface_container
        property color m3surfaceContainerHigh: MainCommon.Config.color.surface_container_high
        property color m3surfaceContainerHighest: MainCommon.Config.color.surface_container_highest
        property color m3onSurface: MainCommon.Config.color.on_surface
        property color m3surfaceVariant: MainCommon.Config.color.surface_variant
        property color m3onSurfaceVariant: MainCommon.Config.color.on_surface_variant
        property color m3inverseSurface: MainCommon.Config.color.inverse_surface
        property color m3inverseOnSurface: MainCommon.Config.color.inverse_on_surface
        property color m3outline: MainCommon.Config.color.outline
        property color m3outlineVariant: MainCommon.Config.color.outline_variant
        property color m3shadow: MainCommon.Config.color.shadow
    }

    property QtObject animation
    property QtObject animationCurves
    property QtObject colors
    property QtObject rounding
    property QtObject font
    property QtObject sizes

    colors: QtObject {
        property color colSubtext: m3colors.m3outline
        property color colLayer0: m3colors.m3background
        property color colOnLayer0: m3colors.m3onBackground
        property color colLayer0Border: ColorUtils.mix(root.m3colors.m3outlineVariant, colLayer0, 0.4)
        property color colLayer1: m3colors.m3surfaceContainerLow
        property color colOnLayer1: m3colors.m3onSurfaceVariant
        property color colOnLayer1Inactive: ColorUtils.mix(colOnLayer1, colLayer1, 0.45)
        property color colLayer1Hover: ColorUtils.mix(colLayer1, colOnLayer1, 0.92)
        property color colLayer1Active: ColorUtils.mix(colLayer1, colOnLayer1, 0.85)
        property color colLayer2: m3colors.m3surfaceContainer
        property color colOnLayer2: m3colors.m3onSurface
        property color colLayer2Hover: ColorUtils.mix(colLayer2, colOnLayer2, 0.90)
        property color colLayer2Active: ColorUtils.mix(colLayer2, colOnLayer2, 0.80)
        property color colLayer2Border: ColorUtils.mix(root.m3colors.m3outlineVariant, colLayer2, 0.4)
        property color colPrimary: m3colors.m3primary
        property color colOnPrimary: m3colors.m3onPrimary
        property color colSecondary: m3colors.m3secondary
        property color colSecondaryContainer: m3colors.m3secondaryContainer
        property color colOnSecondaryContainer: m3colors.m3onSecondaryContainer
        property color colTooltip: m3colors.m3inverseSurface
        property color colOnTooltip: m3colors.m3inverseOnSurface
        property color colShadow: ColorUtils.transparentize(m3colors.m3shadow, 0.7)
        property color colOutline: m3colors.m3outline
    }

    rounding: QtObject {
        property int unsharpen: OverviewCommon.Config.options.appearance.rounding.unsharpen
        property int verysmall: OverviewCommon.Config.options.appearance.rounding.verysmall
        property int small: OverviewCommon.Config.options.appearance.rounding.small
        property int normal: OverviewCommon.Config.options.appearance.rounding.normal
        property int large: OverviewCommon.Config.options.appearance.rounding.large
        property int full: OverviewCommon.Config.options.appearance.rounding.full
        property int screenRounding: OverviewCommon.Config.options.appearance.rounding.screenRounding
        property int windowRounding: OverviewCommon.Config.options.appearance.rounding.windowRounding
    }

    font: QtObject {
        property QtObject family: QtObject {
            property string main: OverviewCommon.Config.options.appearance.font.family.main
            property string title: OverviewCommon.Config.options.appearance.font.family.title
            property string expressive: OverviewCommon.Config.options.appearance.font.family.expressive
        }
        property QtObject pixelSize: QtObject {
            property int smaller: OverviewCommon.Config.options.appearance.font.pixelSize.smaller
            property int small: OverviewCommon.Config.options.appearance.font.pixelSize.small
            property int normal: OverviewCommon.Config.options.appearance.font.pixelSize.normal
            property int larger: OverviewCommon.Config.options.appearance.font.pixelSize.larger
            property int huge: OverviewCommon.Config.options.appearance.font.pixelSize.huge
        }
    }

    animationCurves: QtObject {
        readonly property list<real> expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.00, 1, 1]
        readonly property list<real> expressiveEffects: [0.34, 0.80, 0.34, 1.00, 1, 1]
        readonly property list<real> emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
        readonly property real expressiveDefaultSpatialDuration: OverviewCommon.Config.options.appearance.animation.duration.elementMove
        readonly property real expressiveEffectsDuration: OverviewCommon.Config.options.appearance.animation.duration.elementMoveFast
    }

    animation: QtObject {
        property QtObject elementMove: QtObject {
            property int duration: animationCurves.expressiveDefaultSpatialDuration
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveDefaultSpatial
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMove.duration
                    easing.type: root.animation.elementMove.type
                    easing.bezierCurve: root.animation.elementMove.bezierCurve
                }
            }
        }

        property QtObject elementMoveEnter: QtObject {
            property int duration: OverviewCommon.Config.options.appearance.animation.duration.elementMoveEnter
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasizedDecel
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMoveEnter.duration
                    easing.type: root.animation.elementMoveEnter.type
                    easing.bezierCurve: root.animation.elementMoveEnter.bezierCurve
                }
            }
        }

        property QtObject elementMoveFast: QtObject {
            property int duration: animationCurves.expressiveEffectsDuration
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveEffects
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMoveFast.duration
                    easing.type: root.animation.elementMoveFast.type
                    easing.bezierCurve: root.animation.elementMoveFast.bezierCurve
                }
            }
        }
    }

    sizes: QtObject {
        property real elevationMargin: OverviewCommon.Config.options.appearance.sizes.elevationMargin
    }
}
