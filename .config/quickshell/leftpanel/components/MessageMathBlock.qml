pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qsmath 1.0
import "../../common" as Common
import "../../common/components" as CommonComponents

Item {
  id: root

  property string markdown: ""
  property string rawMarkdown: markdown
  property string selectionKey: ""
  property string activeSelectionKey: ""
  property bool completed: true
  property color textColor: Common.Config.color.on_surface
  property color errorColor: Common.Config.color.error
  readonly property string cacheRoot: {
    const xdg = Quickshell.env("XDG_CACHE_HOME") || ""
    const home = Quickshell.env("HOME") || ""
    return (xdg.length > 0 ? xdg : home + "/.cache") + "/quickshell/latex"
  }
  readonly property bool readyToRender: root.markdown.trim().length > 0
  readonly property real renderScale: Math.max(1, Screen.devicePixelRatio || 1)
  readonly property string renderRequestId: selectionKey + ":" + String(width) + ":" + String(markdown.length) + ":" + String(rawMarkdown.length) + ":" + String(renderScale)
  readonly property int bodyPixelSize: 13

  signal selectionActivated(string selectionKey)

  property string renderState: "idle"
  property string renderError: ""
  property string renderedHtml: ""

  function clearSelection() {
    if (richText.selectedText.length > 0)
      richText.deselect()
    if (fallbackText.selectedText.length > 0)
      fallbackText.deselect()
  }

  function startRender() {
    if (!readyToRender)
      return
    renderState = "loading"
    renderError = ""
    renderedHtml = ""
    renderer.renderMarkdown(renderRequestId, markdown, cacheRoot, Math.max(120, Math.floor(root.width)), bodyPixelSize, 4, String(textColor), renderScale)
  }

  function scheduleRender() {
    if (!readyToRender)
      return
    if (root.completed) {
      renderDebounce.stop()
      startRender()
    } else {
      renderDebounce.restart()
    }
  }

  Timer {
    id: renderDebounce
    interval: 80
    repeat: false
    onTriggered: root.startRender()
  }

  onActiveSelectionKeyChanged: {
    if (activeSelectionKey !== selectionKey)
      clearSelection()
  }
  onMarkdownChanged: scheduleRender()
  onRawMarkdownChanged: scheduleRender()
  onCompletedChanged: scheduleRender()
  onWidthChanged: {
    if (readyToRender)
      scheduleRender()
  }
  onRenderScaleChanged: {
    if (readyToRender)
      scheduleRender()
  }

  implicitWidth: parent ? parent.width : 240
  implicitHeight: richText.visible ? richText.implicitHeight : fallbackText.implicitHeight

  MathRenderer {
    id: renderer

    onRequestFinished: function (requestId, html) {
      if (requestId !== root.renderRequestId)
        return
      root.renderedHtml = html
      root.renderError = ""
      root.renderState = "ready"
    }

    onRequestFailed: function (requestId, error) {
      if (requestId !== root.renderRequestId)
        return
      root.renderState = "error"
      root.renderError = error
    }
  }

  CommonComponents.SelectableTextBlock {
    id: richText
    anchors.fill: parent
    visible: root.renderState === "ready"
    text: root.renderedHtml
    textFormat: TextEdit.RichText
    activeFocusOnPress: false
    activateOnPress: true
    color: root.textColor
    font.family: Common.Config.fontFamily
    font.pixelSize: root.bodyPixelSize
    selectionKey: root.selectionKey
    onSelectionActivated: selectionKey => root.selectionActivated(selectionKey)
  }

  CommonComponents.SelectableTextBlock {
    id: fallbackText
    anchors.fill: parent
    visible: root.renderState !== "ready"
    text: root.renderState === "loading" ? "Rendering equation..." : root.markdown
    textFormat: TextEdit.PlainText
    activeFocusOnPress: false
    color: root.renderState === "error" ? root.errorColor : root.textColor
    font.family: root.renderState === "loading" ? Common.Config.fontFamily : "monospace"
    font.pixelSize: root.bodyPixelSize
    linkCursorEnabled: false
    selectByMouse: root.renderState === "error"
    selectionKey: root.selectionKey
    onSelectionActivated: selectionKey => root.selectionActivated(selectionKey)
  }

  Component.onCompleted: scheduleRender()
}
