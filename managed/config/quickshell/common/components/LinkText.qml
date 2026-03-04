import QtQuick
import Quickshell
import ".." as Common

Text {
  id: root
  linkColor: Common.Config.urlColor
  onLinkActivated: link => Qt.openUrlExternally(link)
}
