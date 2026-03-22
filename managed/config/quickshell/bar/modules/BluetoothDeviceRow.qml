pragma ComponentBehavior: Bound
import "../components"

SystemListRow {
    id: root

    required property var modelData
    required property var moduleRoot
    required property int rowHeight

    readonly property var device: modelData
    readonly property bool connected: !!(device && device.connected)

    active: connected
    leadingIcon: moduleRoot.deviceTypeIcon(device)
    title: moduleRoot.deviceLabel(device)
    trailingIcon: connected ? "󰅖" : "󰐕"
    onClicked: moduleRoot.toggleDeviceConnection(device)
}
