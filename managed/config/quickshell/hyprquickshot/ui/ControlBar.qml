pragma ComponentBehavior: Bound
import QtQuick
import "../common/materialkit" as MK

import "../common" as Common

Rectangle {
  id: root

  required property var colors
  required property string mode // region | window | screen
  required property string recordingState // idle | selecting | countdown | recording
  required property bool screenFrozen
  required property bool saveToDisk
  required property bool recordMode
  required property string audioMode
  required property bool windowModeAvailable
  required property bool windowModeLoading

  signal audioModeSelected(string mode)
  signal modeSelected(string mode)
  signal screenFrozenToggled(bool frozen)
  signal saveToDiskToggled(bool enabled)
  signal recordRequested

  readonly property bool preRecordMode: root.recordingState === "selecting" || root.recordingState === "countdown"
  readonly property bool audioControlVisible: root.preRecordMode
  readonly property bool tooltipActive: root.visible && root.hoveredTooltipTarget !== null && root.hoveredTooltipText !== "" && root.hoveredTooltipTarget.visible
  readonly property real tooltipGap: Common.Config.space.md
  property Item hoveredTooltipTarget: null
  property string hoveredTooltipText: ""
  property string hoveredTooltipTitle: ""
  property real margin: 8

  function audioModeGlyph(mode) {
    if (mode === "defaultMic")
      return ""
    if (mode === "off")
      return ""
    return ""
  }
  function clearTooltipState() {
    hoveredTooltipTarget = null
    hoveredTooltipTitle = ""
    hoveredTooltipText = ""
  }
  function currentAudioModeLabel() {
    if (root.audioMode === "defaultMic")
      return "Microphone"
    if (root.audioMode === "off")
      return "Muted"
    return "Monitor"
  }
  function modeTooltipText(modeValue) {
    if (modeValue === "window")
      return root.windowModeLoading ? "Loading visible windows." : "Capture a single window."
    if (modeValue === "screen")
      return "Capture the full screen."
    return "Capture a selected region."
  }
  function recordTooltipText() {
    if (root.recordingState === "countdown")
      return "Cancel the countdown and go back to screenshot capture."
    if (root.recordingState === "selecting")
      return "Cancel record setup and go back to screenshot capture."
    return "Start screen recording using the current capture mode."
  }
  function syncTooltip(target, title, text, active) {
    if (active) {
      root.hoveredTooltipTarget = target
      root.hoveredTooltipTitle = title
      root.hoveredTooltipText = text
      return
    }
    if (root.hoveredTooltipTarget === target)
      root.clearTooltipState()
  }

  color: Qt.alpha(root.colors.surface, 0.93)
  implicitWidth: contentRoot.implicitWidth + root.margin * 2
  implicitHeight: contentRoot.implicitHeight + root.margin * 2
  radius: 12
  opacity: root.recordingState === "recording" ? 0 : 1
  visible: opacity > 0.05

  Behavior on opacity {
    NumberAnimation {
      duration: 180
      easing.type: Easing.InOutQuad
    }
  }
  onVisibleChanged: {
    if (!visible)
      root.clearTooltipState()
  }
  onRecordingStateChanged: {
    if (root.recordingState === "recording")
      root.clearTooltipState()
  }

  Item {
    id: contentRoot
    anchors.centerIn: parent
    implicitWidth: settingRow.implicitWidth
    implicitHeight: settingRow.implicitHeight

    Row {
      id: settingRow
      anchors.centerIn: parent
      spacing: 16

      Row {
        id: buttonRow
        enabled: root.recordingState !== "recording"
        spacing: 8

        Repeater {
          model: [
            {
              mode: "region",
              icon: "region"
            },
            {
              mode: "window",
              icon: "window"
            },
            {
              mode: "screen",
              icon: "screen"
            }
          ]

          delegate: MK.Button {
            id: modeButton
            required property var modelData
            readonly property bool isWindowMode: modeButton.modelData.mode === "window"

            enabled: true
            implicitHeight: 48
            implicitWidth: 48
            opacity: 1

            background: Rectangle {
              color: {
                if (root.mode === modeButton.modelData.mode)
                  return Qt.alpha(root.colors.primary, 0.5)
                if (modeButton.hovered)
                  return Qt.alpha(root.colors.surface_container_high, 0.5)
                return Qt.alpha(root.colors.surface_container, 0.5)
              }
              radius: 8

              Behavior on color {
                ColorAnimation {
                  duration: 100
                }
              }
            }

            contentItem: Item {
              anchors.fill: parent

              Image {
                anchors.centerIn: parent
                fillMode: Image.PreserveAspectFit
                height: 24
                visible: !(modeButton.isWindowMode && root.windowModeLoading)
                width: 24
                source: Qt.resolvedUrl(`../icons/${modeButton.modelData.icon}.svg`)
              }

              Text {
                anchors.centerIn: parent
                color: root.colors.on_surface
                font.family: Common.Config.iconFontFamily
                font.pixelSize: 22
                text: ""
                visible: modeButton.isWindowMode && root.windowModeLoading
              }
            }

            onClicked: root.modeSelected(modeButton.modelData.mode)
            onHoveredChanged: root.syncTooltip(modeButton, modeButton.modelData.mode === "window" ? "Window" : (modeButton.modelData.mode === "screen" ? "Screen" : "Region"), root.modeTooltipText(modeButton.modelData.mode), hovered)
          }
        }
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.alpha(root.colors.surface_container_high, 0.8)
        height: 32
        width: 1
      }

      Row {
        id: switchRow
        anchors.verticalCenter: buttonRow.verticalCenter
        spacing: 8

        MK.Button {
          id: freezeButton

          Accessible.name: root.screenFrozen ? "Screen frozen" : "Screen live"
          checkable: false
          enabled: root.recordingState !== "countdown" && root.recordingState !== "recording"
          implicitHeight: 48
          implicitWidth: 48

          background: Rectangle {
            color: {
              if (root.screenFrozen)
                return Qt.alpha(root.colors.primary, 0.5)
              if (freezeButton.hovered)
                return Qt.alpha(root.colors.surface_container_high, 0.5)
              return Qt.alpha(root.colors.surface_container, 0.5)
            }
            radius: 8

            Behavior on color {
              ColorAnimation {
                duration: 100
              }
            }
          }

          contentItem: Item {
            anchors.fill: parent

            Text {
              anchors.centerIn: parent
              color: root.colors.on_surface
              font.family: Common.Config.iconFontFamily
              font.pixelSize: 24
              text: root.screenFrozen ? "" : ""
            }
          }

          onClicked: root.screenFrozenToggled(!root.screenFrozen)
          onHoveredChanged: root.syncTooltip(freezeButton, root.screenFrozen ? "Frozen Preview" : "Live Preview", root.screenFrozen ? "Use the frozen frame for precise picks." : "Keep the preview live while choosing what to capture.", hovered)
        }

        MK.Button {
          id: saveButton

          Accessible.name: "Save to disk"
          checkable: false
          enabled: root.recordingState !== "countdown" && root.recordingState !== "recording"
          implicitHeight: 48
          implicitWidth: 48

          background: Rectangle {
            color: {
              if (root.saveToDisk)
                return Qt.alpha(root.colors.primary, 0.5)
              if (saveButton.hovered)
                return Qt.alpha(root.colors.surface_container_high, 0.5)
              return Qt.alpha(root.colors.surface_container, 0.5)
            }
            radius: 8

            Behavior on color {
              ColorAnimation {
                duration: 100
              }
            }
          }

          contentItem: Item {
            anchors.fill: parent

            Image {
              anchors.centerIn: parent
              fillMode: Image.PreserveAspectFit
              height: 24
              width: 24
              source: Qt.resolvedUrl("../icons/save.svg")
            }
          }

          onClicked: root.saveToDiskToggled(!root.saveToDisk)
          onHoveredChanged: root.syncTooltip(saveButton, root.saveToDisk ? "Save to Disk" : "Copy Only", root.saveToDisk ? "Save screenshots to your screenshots directory." : "Copy screenshots to the clipboard without keeping the file.", hovered)
        }

        Row {
          id: recordControls
          spacing: root.audioControlVisible ? 8 : 0

          Behavior on spacing {
            NumberAnimation {
              duration: Common.Config.motion.duration.shortMs
              easing.type: Common.Config.motion.easing.standard
            }
          }

          Item {
            id: audioSlot
            height: 48
            width: root.audioControlVisible ? 56 : 0
            opacity: root.audioControlVisible ? 1 : 0
            scale: root.audioControlVisible ? 1 : 0.9
            visible: width > 0 || opacity > 0.01
            clip: true

            Behavior on width {
              NumberAnimation {
                duration: Common.Config.motion.duration.medium
                easing.type: Common.Config.motion.easing.emphasized
              }
            }

            Behavior on opacity {
              NumberAnimation {
                duration: Common.Config.motion.duration.shortMs
                easing.type: Common.Config.motion.easing.standard
              }
            }

            Behavior on scale {
              NumberAnimation {
                duration: Common.Config.motion.duration.shortMs
                easing.type: Common.Config.motion.easing.standard
              }
            }

            MK.Button {
              id: audioButton

              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              Accessible.name: "Recording audio mode"
              checkable: false
              enabled: root.recordingState !== "recording"
              implicitHeight: 48
              implicitWidth: 56

              background: Rectangle {
                color: {
                  if (root.audioMode !== "off")
                    return Qt.alpha(root.colors.primary, 0.5)
                  if (audioButton.hovered)
                    return Qt.alpha(root.colors.surface_container_high, 0.5)
                  return Qt.alpha(root.colors.surface_container, 0.5)
                }
                radius: 8

                Behavior on color {
                  ColorAnimation {
                    duration: 100
                  }
                }
              }

              contentItem: Item {
                anchors.fill: parent

                Image {
                  anchors.centerIn: parent
                  fillMode: Image.PreserveAspectFit
                  height: 22
                  source: Qt.resolvedUrl("../icons/screen.svg")
                  visible: root.audioMode === "monitor"
                  width: 22
                }

                Text {
                  anchors.centerIn: parent
                  color: root.colors.on_surface
                  font.family: Common.Config.iconFontFamily
                  font.pixelSize: 22
                  text: root.audioModeGlyph(root.audioMode)
                  visible: root.audioMode !== "monitor"
                }
              }

              onClicked: {
                if (root.audioMode === "off")
                  root.audioModeSelected("monitor")
                else if (root.audioMode === "monitor")
                  root.audioModeSelected("defaultMic")
                else
                  root.audioModeSelected("off")
              }
              onHoveredChanged: root.syncTooltip(audioButton, "Audio Mix", `Cycle recording audio source. Current: ${root.currentAudioModeLabel()}.`, hovered)
            }
          }

          MK.Button {
            id: recordButton

            Accessible.name: "Recording indicator"
            checkable: false
            enabled: root.recordingState !== "recording"
            height: 48
            width: 48
            scale: root.recordMode ? 1.05 : 1
            transformOrigin: Item.Center

            background: Rectangle {
              color: {
                if (root.recordMode)
                  return Qt.alpha(root.colors.primary, 0.6)
                if (recordButton.hovered)
                  return Qt.alpha(root.colors.surface_container_high, 0.5)
                return Qt.alpha(root.colors.surface_container, 0.5)
              }
              radius: 8

              Behavior on color {
                ColorAnimation {
                  duration: 100
                }
              }
            }

            contentItem: Item {
              anchors.fill: parent

              Image {
                anchors.centerIn: parent
                fillMode: Image.PreserveAspectFit
                height: 24
                width: 24
                source: root.preRecordMode ? Qt.resolvedUrl("../icons/start.svg") : Qt.resolvedUrl("../icons/record.svg")
              }
            }

            Behavior on scale {
              NumberAnimation {
                duration: 140
                easing.type: Easing.InOutQuad
              }
            }

            onClicked: root.recordRequested()
            onHoveredChanged: root.syncTooltip(recordButton, root.preRecordMode ? "Cancel Recording" : "Start Recording", root.recordTooltipText(), hovered)
          }
        }
      }
    }

    Item {
      id: tooltipLayer
      anchors.fill: parent
      z: 10
      visible: tooltipBubble.opacity > 0.01

      readonly property point anchorPoint: root.hoveredTooltipTarget ? root.mapFromItem(root.hoveredTooltipTarget, root.hoveredTooltipTarget.width / 2, 0) : Qt.point(root.width / 2, 0)

      Rectangle {
        id: tooltipBubble

        readonly property real bubbleWidth: tooltipContent.implicitWidth + (Common.Config.tooltipPadding * 2)
        readonly property real bubbleHeight: tooltipContent.implicitHeight + (Common.Config.tooltipPadding * 2)
        readonly property real baseX: Math.max(0, Math.min(tooltipLayer.width - bubbleWidth, tooltipLayer.anchorPoint.x - (bubbleWidth / 2)))
        readonly property real baseY: tooltipLayer.anchorPoint.y - bubbleHeight - root.tooltipGap

        antialiasing: true
        color: Common.Config.barPopupSurface
        border.width: 1
        border.color: Qt.alpha(root.colors.outline_variant, 0.95)
        height: bubbleHeight
        opacity: root.tooltipActive ? 1 : 0
        radius: Common.Config.tooltipRadius
        scale: root.tooltipActive ? 1 : 0.97
        transformOrigin: Item.Bottom
        visible: opacity > 0.01
        width: bubbleWidth
        x: baseX
        y: baseY

        Behavior on x {
          NumberAnimation {
            duration: Common.Config.motion.duration.shortMs
            easing.type: Common.Config.motion.easing.standard
          }
        }

        Behavior on opacity {
          NumberAnimation {
            duration: Common.Config.motion.duration.shortMs
            easing.type: Common.Config.motion.easing.standard
          }
        }

        Behavior on scale {
          NumberAnimation {
            duration: Common.Config.motion.duration.shortMs
            easing.type: Common.Config.motion.easing.standard
          }
        }

        Column {
          id: tooltipContent
          anchors.fill: parent
          anchors.margins: Common.Config.tooltipPadding
          spacing: 4

          Text {
            color: root.colors.on_surface
            font.family: Common.Config.fontFamily
            font.pixelSize: Common.Config.type.labelLarge.size
            font.weight: Common.Config.type.labelLarge.weight
            text: root.hoveredTooltipTitle
            visible: text !== ""
          }

          Text {
            color: Qt.alpha(root.colors.on_surface, 0.82)
            font.family: Common.Config.fontFamily
            font.pixelSize: Common.Config.type.bodySmall.size
            font.weight: Common.Config.type.bodySmall.weight
            text: root.hoveredTooltipText
            width: Math.min(260, implicitWidth)
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
          }
        }
      }
    }
  }
}
