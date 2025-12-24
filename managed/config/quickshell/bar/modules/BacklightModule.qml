import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../components"

ModuleContainer {
  id: root
  property int sliderValue: 0
  property int brightnessPercent: -1
  property string backlightDevice: "intel_backlight"
  readonly property string actualBrightnessPath: root.backlightDevice !== ""
    ? "/sys/class/backlight/" + root.backlightDevice + "/actual_brightness"
    : ""
  readonly property string maxBrightnessPath: root.backlightDevice !== ""
    ? "/sys/class/backlight/" + root.backlightDevice + "/max_brightness"
    : ""
  property string onScrollUpCommand: "brillo -U 1"
  property string onScrollDownCommand: "brillo -A 1"
  property var icons: [
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "󰃚"
  ]
  readonly property string iconText: root.iconForBrightness()
  tooltipTitle: "Brightness"
  tooltipHoverable: true
  tooltipText: root.brightnessPercent >= 0
    ? root.brightnessPercent + "%"
    : ""
  tooltipContent: Component {
    ColumnLayout {
      spacing: Config.space.sm

      TooltipCard {
        content: [
          RowLayout {
            spacing: Config.space.sm

            IconLabel {
              text: root.iconText
              color: Config.yellow
              font.pixelSize: Config.iconSize + 4
            }

            Text {
              text: root.brightnessPercent >= 0
                ? root.brightnessPercent + "%"
                : "Unavailable"
              color: Config.textColor
              font.family: Config.fontFamily
              font.pixelSize: Config.fontSize + 2
              Layout.fillWidth: true
            }
          },
          LevelSlider {
            Layout.fillWidth: true
            minimum: 1
            maximum: 100
            value: root.sliderValue
            enabled: root.brightnessPercent >= 0
            fillColor: Config.yellow
            onUserChanged: {
              root.sliderValue = Math.round(value)
              root.setBrightness(root.sliderValue)
            }
          }
        ]
      }

      TooltipActionsRow {
        ActionChip { text: "20%"; onClicked: root.setBrightness(20) }
        ActionChip { text: "50%"; onClicked: root.setBrightness(50) }
        ActionChip { text: "80%"; onClicked: root.setBrightness(80) }
        ActionChip { text: "100%"; onClicked: root.setBrightness(100) }
      }
    }
  }

  function iconForBrightness() {
    const percent = root.brightnessPercent
    if (percent < 0)
      return root.icons[root.icons.length - 1]
    const step = 100 / root.icons.length
    const index = Math.min(root.icons.length - 1, Math.floor(percent / step))
    return root.icons[index]
  }

  function updateBrightnessFromFiles() {
    if (root.actualBrightnessPath === "" || root.maxBrightnessPath === "") {
      root.brightnessPercent = -1
      root.sliderValue = 0
      return
    }
    const currentText = actualBrightnessFile.text().trim()
    const maxText = maxBrightnessFile.text().trim()
    const currentValue = parseInt(currentText, 10)
    const maxValue = parseInt(maxText, 10)
    if (!isFinite(currentValue) || !isFinite(maxValue) || maxValue <= 0) {
      root.brightnessPercent = -1
      root.sliderValue = 0
      return
    }
    root.brightnessPercent = Math.round((currentValue / maxValue) * 100)
    root.sliderValue = root.brightnessPercent
  }

  function refreshBrightness() {
    if (root.actualBrightnessPath === "")
      return
    actualBrightnessFile.reload()
    maxBrightnessFile.reload()
  }

  function setBrightness(percent) {
    const next = Math.max(1, Math.min(100, percent))
    Quickshell.execDetached(["sh", "-c", "brillo -S " + next])
  }

  FileView {
    id: actualBrightnessFile
    path: root.actualBrightnessPath
    blockLoading: true
    onTextChanged: root.updateBrightnessFromFiles()
  }

  FileView {
    id: maxBrightnessFile
    path: root.maxBrightnessPath
    blockLoading: true
    onTextChanged: root.updateBrightnessFromFiles()
  }

  Process {
    id: udevMonitor
    command: ["udevadm", "monitor", "--subsystem-match=backlight", "--property"]
    running: root.backlightDevice !== ""
    stdout: SplitParser {
      onRead: function(data) {
        root.refreshBrightness()
      }
    }
  }

  Component.onCompleted: {
    root.refreshBrightness()
  }

  onBacklightDeviceChanged: root.refreshBrightness()

  content: [
    IconLabel { text: root.iconText; color: Config.yellow }
  ]

  MouseArea {
    anchors.fill: parent
    onWheel: function(wheel) {
      if (wheel.angleDelta.y > 0)
        Quickshell.execDetached(["sh", "-c", root.onScrollUpCommand])
      else if (wheel.angleDelta.y < 0)
        Quickshell.execDetached(["sh", "-c", root.onScrollDownCommand])
    }
  }
}
