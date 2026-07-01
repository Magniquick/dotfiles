pragma ComponentBehavior: Bound
import QtQuick
import "../components"
import ".." as Bar

StatusListRow {
  id: root

  required property var modelData
  required property var moduleRoot

  readonly property bool sourceActive: !!modelData && !!modelData.active
  readonly property string sourceName: modelData ? String(modelData.name || "") : ""
  readonly property string sourceType: modelData ? String(modelData.type || "") : ""
  readonly property string sourceDevice: modelData ? String(modelData.device || "") : ""
  readonly property bool connectable: modelData ? !!modelData.connectable : false
  readonly property bool switching: moduleRoot.sourceSwitching && moduleRoot.sourceSwitchingName === root.sourceName

  active: root.sourceActive
  badgeColor: root.switching ? Qt.alpha(Bar.Config.color.secondary, 0.95) : Qt.alpha(Bar.Config.color.tertiary, 0.9)
  badgeText: root.switching ? "SWITCHING" : ""
  badgeTextColor: root.switching ? Bar.Config.color.on_secondary : Bar.Config.color.on_tertiary
  interactive: root.connectable && !root.sourceActive && !root.moduleRoot.sourceSwitching
  leadingIcon: root.moduleRoot.sourceIcon(root.sourceType)
  subtitle: root.sourceDevice !== "" ? (root.moduleRoot.sourceTypeLabel(root.sourceType) + " • " + root.sourceDevice) : root.moduleRoot.sourceTypeLabel(root.sourceType)
  title: root.sourceName !== "" ? root.sourceName : root.moduleRoot.sourceTypeLabel(root.sourceType)

  onClicked: Bar.NetworkService.switchSource(root.modelData)
}
