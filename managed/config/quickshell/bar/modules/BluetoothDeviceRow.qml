pragma ComponentBehavior: Bound
import "../components"

StatusListRow {
  id: root

  required property var modelData
  required property var moduleRoot

  readonly property var device: modelData
  readonly property bool connected: !!(device && device.connected)

  active: connected
  badgeColor: moduleRoot.deviceStatusColor(device)
  badgeText: moduleRoot.deviceStatusBadge(device)
  badgeTextColor: moduleRoot.deviceStatusTextColor(device)
  interactive: moduleRoot.deviceInteractive(device)
  leadingIcon: moduleRoot.deviceTypeIcon(device)
  subtitle: moduleRoot.deviceSubtitle(device)
  title: moduleRoot.deviceLabel(device)
  trailingIcon: moduleRoot.deviceTrailingIcon(device)
  onClicked: moduleRoot.toggleDeviceConnection(device)
}
