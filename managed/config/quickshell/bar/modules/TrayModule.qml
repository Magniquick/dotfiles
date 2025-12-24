import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import ".."
import "../components"

Item {
  id: root
  property var parentWindow

  readonly property var tray: SystemTray
  readonly property var knownIconExtensions: ["png", "svg", "xpm", "jpg", "jpeg"]

  implicitWidth: trayRow.implicitWidth
  implicitHeight: trayRow.implicitHeight

  function iconSource(iconName) {
    if (!iconName)
      return ""
    const pathIndex = iconName.indexOf("?path=")
    if (pathIndex < 0)
      return iconName
    let base = iconName.slice(0, pathIndex)
    const path = iconName.slice(pathIndex + 6).replace(/\/+$/, "")
    if (!path)
      return base
    const schemePrefix = "image://icon/"
    if (base.startsWith(schemePrefix))
      base = base.slice(schemePrefix.length)
    const hasExtension = root.knownIconExtensions.some(ext => base.toLowerCase().endsWith("." + ext))
    if (hasExtension)
      return path + "/" + base
    return path + "/" + base + ".png"
  }

  RowLayout {
    id: trayRow
    spacing: Config.moduleSpacing

    Repeater {
      model: tray.items

      delegate: Item {
        id: trayItem
        implicitWidth: icon.width
        implicitHeight: icon.height
        width: implicitWidth
        height: implicitHeight
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight

        function openTrayMenu() {
          if (!root.parentWindow)
            return
          const rect = root.parentWindow.itemRect(trayItem)
          modelData.display(root.parentWindow, rect.x, rect.y + rect.height)
        }

        Image {
          id: icon
          source: root.iconSource(modelData.icon)
          fillMode: Image.PreserveAspectFit
          width: Config.iconSize + 4
          height: Config.iconSize + 4
          sourceSize.width: width
          sourceSize.height: height
          smooth: true
          mipmap: true
        }

        MouseArea {
          id: toolTipArea
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
          onPressed: {
            if (mouse.button === Qt.RightButton) {
              trayItem.openTrayMenu()
              mouse.accepted = true
            }
          }
          onClicked: {
            if (mouse.button === Qt.MiddleButton) {
              modelData.secondaryActivate()
              return
            }
            if (mouse.button === Qt.LeftButton) {
              if (modelData.onlyMenu)
                trayItem.openTrayMenu()
              else
                modelData.activate()
            }
          }

          onWheel: {
            modelData.scroll(wheel.angleDelta.y, false)
          }
        }

        TooltipPopup {
          targetItem: trayItem
          open: toolTipArea.containsMouse
          enabled: (modelData.tooltipTitle || modelData.tooltipDescription || "") !== ""
          contentComponent: Component {
            Text {
              text: modelData.tooltipTitle || modelData.tooltipDescription || ""
              color: Config.textColor
              font.family: Config.fontFamily
              font.pixelSize: Config.fontSize
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }
  }
}
