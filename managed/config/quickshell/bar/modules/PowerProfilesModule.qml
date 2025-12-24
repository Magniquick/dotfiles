import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import ".."
import "../components"

ModuleContainer {
  id: root
  property int profileIndex: root.indexForProfile(PowerProfiles.profile)
  tooltipTitle: "Power profile"
  tooltipText: ""
  tooltipHoverable: true
  tooltipContent: Component {
    ColumnLayout {
      spacing: Config.space.sm

      TooltipActionsRow {
        ActionChip {
          text: "󰾆"
          active: PowerProfiles.profile === PowerProfile.PowerSaver
          onClicked: root.setProfile(PowerProfile.PowerSaver)
        }

        ActionChip {
          text: "󰾅"
          active: PowerProfiles.profile === PowerProfile.Balanced
          onClicked: root.setProfile(PowerProfile.Balanced)
        }

        ActionChip {
          text: ""
          active: PowerProfiles.profile === PowerProfile.Performance
          onClicked: root.setProfile(PowerProfile.Performance)
        }
      }
    }
  }

  function iconForProfile(profile) {
    if (profile === PowerProfile.Performance)
      return ""
    if (profile === PowerProfile.Balanced)
      return "󰾅"
    if (profile === PowerProfile.PowerSaver)
      return "󰾆"
    return ""
  }

  function profileLabel(profile) {
    if (profile === PowerProfile.Performance)
      return "performance"
    if (profile === PowerProfile.Balanced)
      return "balanced"
    if (profile === PowerProfile.PowerSaver)
      return "power-saver"
    return "unknown"
  }

  function profileTitle(profile) {
    if (profile === PowerProfile.Performance)
      return "Performance"
    if (profile === PowerProfile.Balanced)
      return "Balanced"
    if (profile === PowerProfile.PowerSaver)
      return "Power Saver"
    return "Power profile"
  }

  function indexForProfile(profile) {
    if (profile === PowerProfile.PowerSaver)
      return 0
    if (profile === PowerProfile.Balanced)
      return 1
    return 2
  }

  function profileForIndex(index) {
    if (index <= 0)
      return PowerProfile.PowerSaver
    if (index === 1)
      return PowerProfile.Balanced
    return PowerProfile.Performance
  }

  function setProfile(profile) {
    if (PowerProfiles.profile !== profile)
      PowerProfiles.profile = profile
    root.profileIndex = root.indexForProfile(profile)
  }

  function syncProfile() {
    root.profileIndex = root.indexForProfile(PowerProfiles.profile)
  }

  content: [
    IconLabel { text: root.iconForProfile(PowerProfiles.profile) }
  ]

  onTooltipActiveChanged: {
    if (root.tooltipActive)
      root.syncProfile()
  }

  Connections {
    target: PowerProfiles
    enabled: root.tooltipActive
    function onProfileChanged() {
      root.syncProfile()
    }
  }
}
