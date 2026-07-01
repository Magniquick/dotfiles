import QtQuick
import ".." as Common

TextEdit {
  id: root

  property bool linkCursorEnabled: true
  property bool activateOnPress: false
  property string selectionKey: ""

  signal selectionActivated(string selectionKey)

  activeFocusOnPress: true
  color: Common.Config.color.on_surface
  cursorVisible: false
  font.family: Common.Config.fontFamily
  font.pixelSize: Common.Config.type.bodyMedium.size
  readOnly: true
  selectByMouse: true
  selectedTextColor: Common.Config.color.on_primary
  selectionColor: Common.Config.color.primary
  wrapMode: TextEdit.Wrap

  onLinkActivated: link => Qt.openUrlExternally(link)
  onSelectedTextChanged: {
    if (selectedText.length > 0)
      root.selectionActivated(root.selectionKey)
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    cursorShape: root.linkCursorEnabled && parent.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor
    hoverEnabled: true
  }

  TapHandler {
    acceptedButtons: Qt.LeftButton
    enabled: root.activateOnPress
    onPressedChanged: {
      if (pressed)
        root.selectionActivated(root.selectionKey)
    }
  }
}
