/**
 * @module BatteryModule
 * @description Battery status module with UPower integration
 *
 * Features:
 * - Battery percentage and charging state display
 * - Time remaining estimates (charging/discharging)
 * - Battery health percentage tracking
 * - Power profile quick switcher (PowerSaver/Balanced/Performance)
 * - Click toggles time/percentage display
 *
 * Dependencies:
 * - Quickshell.Services.UPower: Battery state and power profiles
 */
pragma ComponentBehavior: Bound
import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qsnative

ModuleContainer {
  id: root

  property int healthPercent: -1
  property bool showTime: false
  property bool chargeControlApplying: false
  property bool chargeControlAvailable: false
  property bool chargeControlWaitingForApplyRefresh: false
  property string chargeControlMode: ""

  BarModuleLogic {
    id: uiLogic
  }

  function normalizePercent(value) {
    if (!isFinite(value))
      return 0
    return value <= 1 ? value * 100 : value
  }

  function batteryColor(device) {
    if (!device || !device.ready)
      return Config.color.on_surface

    if (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge)
      return Config.color.tertiary

    if (device.state === UPowerDeviceState.Discharging || device.state === UPowerDeviceState.PendingDischarge)
      return Config.color.error

    return Config.color.on_surface
  }
  function batteryIcon(device) {
    if (!device || !device.ready)
      return ""

    if (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge)
      return "󰂄"

    const percent = root.normalizePercent(device.percentage)
    if (percent <= 10)
      return "󰁺"

    if (percent <= 20)
      return "󰁻"

    if (percent <= 30)
      return "󰁼"

    if (percent <= 40)
      return "󰁽"

    if (percent <= 50)
      return "󰁾"

    if (percent <= 60)
      return "󰁿"

    if (percent <= 70)
      return "󰂀"

    if (percent <= 80)
      return "󰂁"

    if (percent <= 90)
      return "󰂂"

    return "󰁹"
  }
  function batteryPercentValue(device) {
    if (!device || !device.ready)
      return 0

    const percent = root.normalizePercent(device.percentage)
    return Math.max(0, Math.min(100, percent))
  }
  function formatSeconds(seconds) {
    if (!seconds || seconds <= 0)
      return ""

    const totalMinutes = Math.floor(seconds / 60)
    const hours = Math.floor(totalMinutes / 60)
    const minutes = totalMinutes % 60
    if (hours <= 0)
      return minutes + "m"

    if (minutes <= 0)
      return hours + "h"

    return hours + "h " + minutes + "m"
  }
  function healthFromDevice(device) {
    if (!device)
      return -1

    if (!device.ready)
      return -1

    const healthRaw = device.healthPercentage
    const health = root.normalizePercent(healthRaw)
    if (isFinite(health) && health > 0)
      return Math.round(health)

    // Fallback: if we at least have a full-capacity reading, assume design==full (100%).
    const full = device.energyCapacity
    if (isFinite(full) && full > 0)
      return 100

    // As a last resort, derive full from energy + percentage and assume design==full.
    const percent = root.normalizePercent(device.percentage)
    const percentFrac = percent / 100
    if (isFinite(device.energy) && isFinite(percentFrac) && percentFrac > 0)
      return 100

    return -1
  }
  function healthLabel() {
    return root.healthPercent >= 0 ? root.healthPercent + "%" : "—"
  }
  function chargeControlIsLimit() {
    return root.chargeControlMode === "limit"
  }
  function chargeControlBusy() {
    return root.chargeControlApplying || chargeControlRunner.running || chargeControlConfigRunner.running
  }
  function refreshChargeControl() {
    if (root.chargeControlAvailable)
      chargeControlConfigRunner.trigger()
  }
  function toggleChargeControlLimit() {
    if (!root.chargeControlAvailable || root.chargeControlBusy() || root.chargeControlMode === "")
      return
    root.chargeControlApplying = true
    root.chargeControlWaitingForApplyRefresh = false
    root.chargeControlMode = root.chargeControlIsLimit() ? "auto" : "limit"
    chargeControlRunner.command = uiLogic.chargeControlCommand(root.chargeControlMode)
    chargeControlRunner.trigger()
  }
  function updateChargeControlConfig(output) {
    root.chargeControlMode = String(uiLogic.parseChargeControlConfig(String(output || "")).mode || "").toLowerCase()
    if (root.chargeControlWaitingForApplyRefresh) {
      root.chargeControlWaitingForApplyRefresh = false
      root.chargeControlApplying = false
    }
  }
  function percentLabel(device) {
    if (!device || !device.ready)
      return ""

    const percent = root.normalizePercent(device.percentage)
    return Math.round(percent) + "%"
  }
  function refreshHealth() {
    const fromDevice = root.healthFromDevice(UPower.displayDevice)
    if (fromDevice >= 0)
      root.healthPercent = fromDevice
  }
  function stateLabel(device) {
    if (!device || !device.ready)
      return "Unknown"

    const timeRemaining = root.timeRemainingLabel(device)
    switch (device.state) {
    case UPowerDeviceState.Charging:
    case UPowerDeviceState.PendingCharge:
      return "Charging" + (timeRemaining ? (" · " + timeRemaining) : "")
    case UPowerDeviceState.Discharging:
    case UPowerDeviceState.PendingDischarge:
      return "Discharging" + (timeRemaining ? (" · " + timeRemaining) : "")
    case UPowerDeviceState.FullyCharged:
      return "Full"
    default:
      return "Idle"
    }
  }
  function timeLabel(device) {
    if (!device || !device.ready)
      return ""

    const time = device.timeToEmpty > 0 ? device.timeToEmpty : device.timeToFull
    const formatted = formatSeconds(time)
    return formatted ? formatted : ""
  }
  function timeRemainingLabel(device) {
    if (!device || !device.ready)
      return ""

    const isCharging = device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge
    const isDischarging = device.state === UPowerDeviceState.Discharging || device.state === UPowerDeviceState.PendingDischarge
    let seconds = 0
    if (isCharging)
      seconds = device.timeToFull
    else if (isDischarging)
      seconds = device.timeToEmpty
    const formatted = root.formatSeconds(seconds)
    return formatted ? formatted + " left" : ""
  }
  function tooltipLabel() {
    const device = UPower.displayDevice
    if (!device || !device.ready)
      return "Battery: unknown"

    const percentText = root.percentLabel(device)
    const timeText = root.timeLabel(device)
    const timeSuffix = timeText ? " (" + timeText + ")" : ""
    return "Battery: " + percentText + timeSuffix
  }

  tooltipHoverable: true
  tooltipText: root.tooltipLabel()
  tooltipTitle: "Battery"

  content: [
    IconTextRow {
      iconColor: root.batteryColor(UPower.displayDevice)
      iconText: root.batteryIcon(UPower.displayDevice)
      spacing: root.contentSpacing
      text: root.showTime ? root.timeLabel(UPower.displayDevice) : root.percentLabel(UPower.displayDevice)
      textColor: root.batteryColor(UPower.displayDevice)
    }
  ]
  tooltipContent: Component {
    ColumnLayout {
      spacing: Config.space.md
      width: 240 // Match CalendarTooltip width

      // Header Section
      TooltipHeader {
        icon: root.batteryIcon(UPower.displayDevice)
        iconColor: root.batteryColor(UPower.displayDevice)
        subtitle: root.stateLabel(UPower.displayDevice)
        title: root.percentLabel(UPower.displayDevice)
      }
      ProgressBar {
        Layout.fillWidth: true
        fillColor: root.batteryColor(UPower.displayDevice)
        Layout.preferredHeight: Config.space.xs
        implicitHeight: Config.space.xs
        trackColor: Config.color.surface_variant
        value: root.batteryPercentValue(UPower.displayDevice) / 100
      }

      // Power Mode Section
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Config.space.xs

        SectionHeader {
          text: "POWER PROFILE"
        }
        TooltipActionsRow {
          spacing: Config.space.sm

          ActionChip {
            Layout.fillWidth: true
            active: PowerProfiles.profile === PowerProfile.PowerSaver
            text: "󰾆"

            onClicked: PowerProfiles.profile = PowerProfile.PowerSaver
          }
          ActionChip {
            Layout.fillWidth: true
            active: PowerProfiles.profile === PowerProfile.Balanced
            text: "󰾅"

            onClicked: PowerProfiles.profile = PowerProfile.Balanced
          }
          ActionChip {
            Layout.fillWidth: true
            active: PowerProfiles.profile === PowerProfile.Performance
            text: ""

            onClicked: PowerProfiles.profile = PowerProfile.Performance
          }
        }
      }

      // Charge Policy Section
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Config.space.xs

        SectionHeader {
          text: "CHARGE POLICY"
        }
        Item {
          id: chargePolicyRow

          Layout.fillWidth: true
          implicitHeight: Config.space.xxl
          opacity: root.chargeControlAvailable && !root.chargeControlBusy() ? 1 : Config.state.disabledOpacity

          RowLayout {
            anchors.fill: parent
            spacing: Config.space.md

            Text {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              color: chargePolicyMouse.containsMouse && !root.chargeControlBusy() ? Config.color.on_surface : Config.color.on_surface_variant
              elide: Text.ElideRight
              font.family: Config.fontFamily
              font.pixelSize: Config.type.labelLarge.size
              font.weight: Config.type.labelLarge.weight
              text: "Battery care"

              Behavior on color {
                ColorAnimation {
                  duration: Config.motion.duration.shortMs
                  easing.type: Config.motion.easing.standard
                }
              }
            }
            Rectangle {
              id: chargePolicyTrack

              Layout.alignment: Qt.AlignVCenter
              implicitHeight: Config.space.xl
              implicitWidth: Config.space.xxl + Config.space.lg
              antialiasing: true
              color: root.chargeControlBusy() ? Qt.alpha(Config.color.on_surface_variant, 0.18) : (root.chargeControlIsLimit() ? Config.color.primary : Qt.alpha(Config.color.on_surface_variant, chargePolicyMouse.containsMouse ? 0.36 : 0.24))
              radius: height / 2

              Behavior on color {
                ColorAnimation {
                  duration: Config.motion.duration.shortMs
                  easing.type: Config.motion.easing.standard
                }
              }

              Rectangle {
                height: parent.height - Config.space.xs
                width: height
                anchors.verticalCenter: parent.verticalCenter
                antialiasing: true
                color: root.chargeControlBusy() ? Config.color.surface_container_highest : (root.chargeControlIsLimit() ? Config.color.on_primary : Config.color.surface)
                radius: height / 2
                x: root.chargeControlIsLimit() ? chargePolicyTrack.width - width - (Config.space.xs / 2) : (Config.space.xs / 2)

                Behavior on x {
                  NumberAnimation {
                    duration: Config.motion.duration.shortMs
                    easing.type: Config.motion.easing.emphasized
                  }
                }
              }
            }
          }
          MouseArea {
            id: chargePolicyMouse

            anchors.fill: parent
            cursorShape: root.chargeControlAvailable && !root.chargeControlBusy() && root.chargeControlMode !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: root.chargeControlAvailable && !root.chargeControlBusy() && root.chargeControlMode !== ""
            hoverEnabled: true

            onClicked: root.toggleChargeControlLimit()
          }
        }
      }

      // Health Section
      InfoRow {
        Layout.fillWidth: true
        icon: "󰁹"
        label: "Battery Health"
        opacity: 0.6
        showLeader: false
        value: root.healthLabel()
      }
    }
  }

  CommandRunner {
    id: chargeControlConfigRunner

    command: ["/usr/local/bin/hp-charge-control", "config", "show"]
    enabled: root.chargeControlAvailable
    intervalMs: 0
    timeoutMs: 2000

    onError: function (errorOutput, exitCode) {
      root.chargeControlWaitingForApplyRefresh = false
      root.chargeControlApplying = false
    }
    onRan: function (output) {
      root.updateChargeControlConfig(output)
    }
    onTimeout: {
      root.chargeControlWaitingForApplyRefresh = false
      root.chargeControlApplying = false
    }
  }
  CommandRunner {
    id: chargeControlRunner

    enabled: root.chargeControlAvailable
    intervalMs: 0
    timeoutMs: 5000

    onError: function (errorOutput, exitCode) {
      root.chargeControlWaitingForApplyRefresh = false
      root.chargeControlApplying = false
      root.refreshChargeControl()
    }
    onRan: function (output) {
      root.chargeControlWaitingForApplyRefresh = true
      root.refreshChargeControl()
    }
    onTimeout: {
      root.chargeControlWaitingForApplyRefresh = false
      root.chargeControlApplying = false
      root.refreshChargeControl()
    }
  }
  Component.onCompleted: {
    root.refreshHealth()
    DependencyCheck.requireExecutable("/usr/local/bin/hp-charge-control", "BatteryModule", function (available) {
      root.chargeControlAvailable = available
      if (available)
        root.refreshChargeControl()
    })
  }
  onTooltipActiveChanged: {
    if (root.tooltipActive) {
      root.refreshHealth()
      root.refreshChargeControl()
    }
  }

  Connections {
    function onEnergyCapacityChanged() {
      root.refreshHealth()
    }
    function onHealthPercentageChanged() {
      root.refreshHealth()
    }
    function onPercentageChanged() {
      root.refreshHealth()
    }
    function onReadyChanged() {
      root.refreshHealth()
    }

    ignoreUnknownSignals: true
    target: UPower.displayDevice
  }

  onClicked: root.showTime = !root.showTime
}
