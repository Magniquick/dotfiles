pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import materialpopups 1.0 as MaterialPopups
import "../common" as Common
import "../common/materialkit" as MK

PanelWindow {
  id: root

  readonly property int windowWidth: 240
  readonly property int windowHeight: 136
  readonly property int contentHeight: 116
  readonly property int cardSize: 80
  readonly property int cardLeft: 24
  readonly property int cardTop: 20
  readonly property int frameLeft: 20
  readonly property int frameTop: 16
  readonly property int frameSize: 88
  readonly property int pillLeft: 12
  readonly property int pillTop: 48
  readonly property int pillWidth: 224
  readonly property int pillHeight: 64
  readonly property int circleSize: 48
  readonly property int dismissSize: 32
  readonly property int visibleTimeoutMs: 6000
  readonly property int copyKeyGraceMs: 400
  property string copiedText: ""
  property double lastCopyAt: 0
  property bool popupVisible: false
  property bool popupExiting: false
  property int lastObservedCopySerial: 0
  property int lastObservedActivitySerial: 0
  property string lastObservedError: ""

  color: "transparent"
  visible: Common.Config.clipboardPopupEnabled && (popupVisible || popupExiting)
  screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  implicitWidth: windowWidth
  implicitHeight: windowHeight
  exclusiveZone: 0

  WlrLayershell.namespace: "quickshell:clipboard-popup"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  anchors {
    left: true
    bottom: true
  }

  function showText(text) {
    const value = String(text || "").trim()
    if (value === "")
      return
    exitAnimation.stop()
    enterAnimation.stop()
    copiedText = value
    lastCopyAt = Date.now()
    popupVisible = true
    popupExiting = false
    dismissTimer.restart()
    enterAnimation.restart()
  }

  function dismiss() {
    if (!popupVisible || popupExiting)
      return
    enterAnimation.stop()
    popupExiting = true
    popupVisible = false
    dismissTimer.stop()
    exitAnimation.restart()
  }

  function handleActivity() {
    if (!popupVisible || popupExiting)
      return
    if (Date.now() - lastCopyAt <= copyKeyGraceMs)
      return
    dismiss()
  }

  function invokeAction(command) {
    const trimmed = String(command || "").trim()
    if (trimmed !== "")
      Common.ProcessHelper.execDetached(trimmed + " " + shellQuote(copiedText))
    dismiss()
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  Component.onCompleted: {
    if (Common.Config.clipboardPopupEnabled)
      backend.start()
  }

  Component.onDestruction: backend.stop()

  onVisibleChanged: {
    if (!visible && !popupExiting)
      dismissTimer.stop()
  }

  MaterialPopups.MaterialPopupBackend {
    id: backend
  }

  Timer {
    interval: 50
    repeat: true
    running: Common.Config.clipboardPopupEnabled
    onTriggered: {
      if (backend.copySerial !== root.lastObservedCopySerial) {
        root.lastObservedCopySerial = backend.copySerial
        root.showText(backend.lastText)
      }

      if (backend.activitySerial !== root.lastObservedActivitySerial) {
        root.lastObservedActivitySerial = backend.activitySerial
        root.handleActivity()
      }

      if (backend.error !== "" && backend.error !== root.lastObservedError) {
        root.lastObservedError = backend.error
        console.warn("ClipboardPopup backend:", backend.error)
      }
    }
  }

  Timer {
    id: dismissTimer

    interval: root.visibleTimeoutMs
    repeat: false
    onTriggered: root.dismiss()
  }

  ParallelAnimation {
    id: enterAnimation

    alwaysRunToEnd: false
    onStarted: {
      content.opacity = 0
      content.y = 20
    }

    OpacityAnimator {
      target: content
      from: 0
      to: 1
      duration: 283
      easing.type: Easing.OutQuad
    }
    YAnimator {
      target: content
      from: 20
      to: 0
      duration: 283
      easing.type: Easing.OutQuad
    }
  }

  ParallelAnimation {
    id: exitAnimation

    alwaysRunToEnd: false
    onFinished: {
      root.popupExiting = false
      content.opacity = 0
      content.y = 20
    }

    OpacityAnimator {
      target: content
      from: 1
      to: 0
      duration: 166
      easing.type: Easing.InQuad
    }
    YAnimator {
      target: content
      from: 0
      to: 20
      duration: 166
      easing.type: Easing.InQuad
    }
  }

  Item {
    id: content

    width: root.windowWidth
    height: root.contentHeight
    opacity: 0
    y: 20
    visible: root.popupVisible || root.popupExiting

    MK.ClickableSurface {
      id: pill

      x: root.pillLeft
      y: root.pillTop
      width: root.pillWidth
      height: root.pillHeight
      radius: height / 2
      backgroundColor: Common.Config.color.surface_container_high
      hoverBackgroundColor: Common.Config.color.surface_container_high
      pressedBackgroundColor: Common.Config.color.surface_container_high
      rippleWaveEnabled: false
      rippleStateLayerEnabled: false
      cursorShape: Qt.ArrowCursor
      onClicked: mouse => mouse.accepted = false

      Row {
        x: 108
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        ClipboardActionButton {
          iconText: Common.Config.clipboardPopupLeftIcon
          onActionTriggered: root.invokeAction(Common.Config.clipboardPopupLeftCommand)
        }

        ClipboardActionButton {
          iconText: Common.Config.clipboardPopupRightIcon
          onActionTriggered: root.invokeAction(Common.Config.clipboardPopupRightCommand)
        }
      }
    }

    Rectangle {
      id: frame

      x: root.frameLeft
      y: root.frameTop
      width: root.frameSize
      height: root.frameSize
      radius: 26
      color: Common.Config.color.surface_container_high
      border.width: 0
    }

    MK.ClickableSurface {
      id: card

      x: root.cardLeft
      y: root.cardTop
      width: root.cardSize
      height: root.cardSize
      radius: 22
      backgroundColor: Common.Config.color.secondary
      hoverBackgroundColor: Qt.alpha(Common.Config.color.secondary, 0.94)
      pressedBackgroundColor: Qt.alpha(Common.Config.color.secondary, 0.88)
      rippleColor: Common.Config.color.on_secondary
      onClicked: root.dismiss()

      Text {
        anchors.fill: parent
        anchors.margins: 9
        text: root.previewText(root.copiedText)
        color: Common.Config.color.on_secondary
        font.family: Common.Config.fontFamily
        font.pixelSize: 13
        font.weight: Font.Normal
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        lineHeight: 1.0
        wrapMode: Text.WrapAnywhere
        maximumLineCount: 4
        elide: Text.ElideRight
      }
    }

    MK.ClickableSurface {
      id: dismissButton

      x: root.cardLeft + root.cardSize - root.dismissSize / 2
      y: root.cardTop - root.dismissSize / 2
      width: root.dismissSize
      height: root.dismissSize
      radius: height / 2
      backgroundColor: Common.Config.color.secondary_fixed
      hoverBackgroundColor: Qt.alpha(Common.Config.color.secondary_fixed, 0.94)
      pressedBackgroundColor: Qt.alpha(Common.Config.color.secondary_fixed, 0.88)
      rippleColor: Common.Config.color.on_secondary_fixed
      onClicked: root.dismiss()

      Text {
        anchors.centerIn: parent
        text: "󰅖"
        color: Common.Config.color.on_secondary_fixed
        font.family: Common.Config.iconFontFamily
        font.pixelSize: 18
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  component ClipboardActionButton: MK.ClickableSurface {
    id: actionRoot

    property string iconText: ""
    signal actionTriggered

    width: root.circleSize
    height: root.circleSize
    radius: height / 2
    backgroundColor: Common.Config.color.secondary
    hoverBackgroundColor: Qt.alpha(Common.Config.color.secondary, 0.94)
    pressedBackgroundColor: Qt.alpha(Common.Config.color.secondary, 0.88)
    rippleColor: Common.Config.color.on_secondary
    onClicked: actionRoot.actionTriggered()

    Text {
      anchors.centerIn: parent
      text: actionRoot.iconText
      color: Common.Config.color.on_secondary
      font.family: Common.Config.iconFontFamily
      font.pixelSize: 24
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }
  }

  function previewText(text) {
    const maxLines = 4
    const maxChars = 10
    const lines = []
    const sourceLines = String(text || "").split(/\r?\n/)

    for (let i = 0; i < sourceLines.length && lines.length < maxLines; i++) {
      const rawWords = sourceLines[i].trim().split(/\s+/).filter(word => word !== "")
      let current = ""
      for (let w = 0; w < rawWords.length && lines.length < maxLines; w++) {
        const tokens = root.previewTokens(rawWords[w])
        for (let t = 0; t < tokens.length && lines.length < maxLines; t++) {
          const word = tokens[t]
          if (current === "") {
            if (word.length > maxChars) {
              const chunks = root.wrapToken(word, maxChars)
              for (let c = 0; c < chunks.length && lines.length < maxLines; c++)
                lines.push(chunks[c])
              current = ""
            } else {
              current = word
            }
            continue
          }

          if (current.length + 1 + word.length > maxChars) {
            lines.push(current)
            current = word.length > maxChars ? "" : word
            if (word.length > maxChars) {
              const wrapped = root.wrapToken(word, maxChars)
              for (let j = 0; j < wrapped.length && lines.length < maxLines; j++)
                lines.push(wrapped[j])
            }
          } else {
            current += " " + word
          }
        }
      }

      if (current !== "" && lines.length < maxLines)
        lines.push(current)
    }

    if (lines.length === 0)
      return String(text || "").slice(0, maxChars)
    return lines.slice(0, maxLines).join("\n")
  }

  function previewTokens(word) {
    if (word.startsWith("--") && word.length > 2)
      return ["--", word.slice(2)]
    return [word]
  }

  function wrapToken(word, maxChars) {
    const chunks = []
    for (let i = 0; i < word.length; i += maxChars)
      chunks.push(word.slice(i, i + maxChars))
    return chunks
  }
}
