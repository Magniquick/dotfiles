import ".."
import QtQuick

ActionButtonBase {
    id: root

    property string icon: ""

    disabledOpacity: Config.state.disabledOpacity
    inactiveColor: Config.barPopupInnerSurface
    hoverColor: Config.barPopupInnerSurface
    height: Config.space.xl + Config.space.sm
    radius: width / 2
    width: Config.space.xl + Config.space.sm

    Text {
        anchors.centerIn: parent
        color: root.active ? Config.color.on_surface : Config.color.on_surface_variant
        font.family: Config.iconFontFamily
        font.pixelSize: Config.type.titleMedium.size
        text: root.icon
    }
}
