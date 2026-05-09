pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qsmath 1.0
import "../../common" as Common

Item {
  id: root

  property string markdown: ""
  property string selectionKey: ""
  property string activeSelectionKey: ""
  property bool completed: true
  property color textColor: Common.Config.color.on_surface
  property color errorColor: Common.Config.color.error
  readonly property string cacheRoot: {
    const xdg = Quickshell.env("XDG_CACHE_HOME") || "";
    const home = Quickshell.env("HOME") || "";
    return (xdg.length > 0 ? xdg : home + "/.cache") + "/quickshell/latex";
  }
  readonly property bool readyToRender: root.completed && root.markdown.trim().length > 0
  readonly property real renderScale: Math.max(1, Screen.devicePixelRatio || 1)
  readonly property string renderRequestId: selectionKey + ":" + String(width) + ":" + String(markdown.length) + ":" + String(renderScale)
  readonly property int bodyPixelSize: 13

  signal selectionActivated(string selectionKey)

  property string renderState: "idle"
  property string renderError: ""
  property string renderedHtml: ""

  function clearSelection() {
    if (richText.selectedText.length > 0)
      richText.deselect();
    if (fallbackText.selectedText.length > 0)
      fallbackText.deselect();
  }

  function startRender() {
    if (!readyToRender)
      return;
    renderState = "loading";
    renderError = "";
    renderedHtml = "";
    renderer.renderMarkdown(
      renderRequestId,
      markdown,
      cacheRoot,
      Math.max(120, Math.floor(root.width)),
      bodyPixelSize,
      4,
      String(textColor),
      renderScale
    );
  }

  onActiveSelectionKeyChanged: {
    if (activeSelectionKey !== selectionKey)
      clearSelection();
  }
  onMarkdownChanged: startRender()
  onCompletedChanged: startRender()
  onWidthChanged: {
    if (readyToRender)
      startRender();
  }
  onRenderScaleChanged: {
    if (readyToRender)
      startRender();
  }

  implicitWidth: parent ? parent.width : 240
  implicitHeight: richText.visible ? richText.implicitHeight : fallbackText.implicitHeight

  MathRenderer {
    id: renderer

    onRequestFinished: function(requestId, html) {
      if (requestId !== root.renderRequestId)
        return;
      root.renderedHtml = html;
      root.renderError = "";
      root.renderState = "ready";
    }

    onRequestFailed: function(requestId, error) {
      if (requestId !== root.renderRequestId)
        return;
      root.renderState = "error";
      root.renderError = error;
    }
  }

  TextEdit {
    id: richText
    anchors.fill: parent
    visible: root.renderState === "ready"
    text: root.renderedHtml
    textFormat: TextEdit.RichText
    color: root.textColor
    wrapMode: TextEdit.Wrap
    font.family: Common.Config.fontFamily
    font.pixelSize: root.bodyPixelSize
    readOnly: true
    selectByMouse: true
    cursorVisible: false
    activeFocusOnPress: false

    onLinkActivated: link => Qt.openUrlExternally(link)
    onSelectedTextChanged: {
      if (selectedText.length > 0)
        root.selectionActivated(root.selectionKey);
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.NoButton
      hoverEnabled: true
      cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor
    }

    TapHandler {
      acceptedButtons: Qt.LeftButton
      onPressedChanged: {
        if (pressed)
          root.selectionActivated(root.selectionKey);
      }
    }
  }

  TextEdit {
    id: fallbackText
    anchors.fill: parent
    visible: root.renderState !== "ready"
    text: root.renderState === "loading"
      ? "Rendering equation..."
      : root.markdown
    textFormat: TextEdit.PlainText
    color: root.renderState === "error" ? root.errorColor : root.textColor
    wrapMode: TextEdit.Wrap
    font.family: root.renderState === "loading" ? Common.Config.fontFamily : "monospace"
    font.pixelSize: root.bodyPixelSize
    readOnly: true
    selectByMouse: root.renderState === "error"
    cursorVisible: false
    activeFocusOnPress: false

    onSelectedTextChanged: {
      if (selectedText.length > 0)
        root.selectionActivated(root.selectionKey);
    }
  }

  Component.onCompleted: startRender()
}
