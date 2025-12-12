import QtQuick
import QtQuick.Layouts

Item {
  id: gridHolder
  property var colors: ColorPalette.palette
  property var actions: defaultActions()
  property string selection: ""
  property string hoverAction: ""
  property bool reveal: false
  property bool hoverEnabled: true
  property bool suppressNextHover: false
  // Local flag so we don't break the upstream binding when consuming the first hover.
  property bool dropNextHover: suppressNextHover
  property int columns: 3
  property int iconPadding: 6

  onSuppressNextHoverChanged: dropNextHover = suppressNextHover

  signal hovered(string actionName)
  signal unhovered()
  signal activated(string actionName)

  implicitWidth: grid.implicitWidth
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.centerIn: parent
    columns: gridHolder.columns
    columnSpacing: gridHolder.iconPadding
    rowSpacing: gridHolder.iconPadding

    Repeater {
      model: gridHolder.actions
      delegate: PowermenuButton {
        actionName: modelData.name
        icon: modelData.icon
        accent: modelData.accent
        selection: gridHolder.selection
        hoverAction: gridHolder.hoverAction
        reveal: gridHolder.reveal
        revealDelay: 80 * index
        onHovered: (action) => {
          if (gridHolder.dropNextHover) {
            gridHolder.dropNextHover = false
            return
          }
          gridHolder.hovered(action)
        }
        onUnhovered: () => gridHolder.unhovered()
        onActivated: (action) => gridHolder.activated(action)
        mouseEnabled: gridHolder.hoverEnabled
      }
    }
  }

  function defaultActions() {
    return [
      ({ name: "Poweroff", icon: "", accent: colors.red }),
      ({ name: "Reboot", icon: "", accent: colors.green }),
      ({ name: "Exit", icon: "󰿅", accent: colors.pink }),
      ({ name: "Hibernate", icon: "󰒲", accent: colors.teal }),
      ({ name: "Suspend", icon: "󰤄", accent: colors.yellow }),
      ({ name: "Windows", icon: "", accent: colors.blue })
    ]
  }
}
