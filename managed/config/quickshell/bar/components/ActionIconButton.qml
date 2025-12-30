import ".."
import QtQuick

ActionButtonBase {
    id: root

    property string icon: ""

    disabledOpacity: Config.state.disabledOpacity
    height: Config.space.xl + Config.space.sm
    radius: width / 2
    width: Config.space.xl + Config.space.sm

    Text {
        anchors.centerIn: parent
        color: root.active ? Config.m3.onSurface : Config.m3.onSurfaceVariant
        font.family: Config.iconFontFamily
        font.pixelSize: Config.type.titleMedium.size
        text: root.icon
    }
}
