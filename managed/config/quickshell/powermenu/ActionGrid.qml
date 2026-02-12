pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

Item {
    id: gridHolder

    property var actions: defaultActions()
    property var colors
    property int columns: 3
    // Local flag (not bound) so consuming the first hover does not break bindings.
    property bool dropNextHover: false
    property string hoverAction: ""
    property bool hoverEnabled: true
    property int iconPadding: 6
    property bool reveal: false
    property string selection: ""
    property bool suppressNextHover: false

    signal activated(string actionName)
    signal hovered(string actionName)
    signal unhovered

    function defaultActions() {
        return [({
                    "name": "Poweroff",
                    "icon": "",
                    "accent": colors.error
                }), ({
                    "name": "Reboot",
                    "icon": "",
                    "accent": colors.tertiary
                }), ({
                    "name": "Exit",
                    "icon": "󰿅",
                    "accent": colors.secondary
                }), ({
                    "name": "Hibernate",
                    "icon": "󰒲",
                    "accent": colors.tertiary
                }), ({
                    "name": "Suspend",
                    "icon": "󰤄",
                    "accent": colors.secondary
                }), ({
                    "name": "Windows",
                    "icon": "",
                    "accent": colors.primary
                })];
    }

    implicitHeight: grid.implicitHeight
    implicitWidth: grid.implicitWidth

    onSuppressNextHoverChanged: dropNextHover = suppressNextHover

    GridLayout {
        id: grid

        anchors.centerIn: parent
        columnSpacing: gridHolder.iconPadding
        columns: gridHolder.columns
        rowSpacing: gridHolder.iconPadding

        Repeater {
            model: gridHolder.actions

            delegate: PowermenuButton {
                required property var modelData
                required property int index

                accent: modelData.accent
                actionName: modelData.name
                hoverAction: gridHolder.hoverAction
                icon: modelData.icon
                mouseEnabled: gridHolder.hoverEnabled
                reveal: gridHolder.reveal
                revealDelay: 80 * index
                selection: gridHolder.selection

                onActivated: action => {
                    return gridHolder.activated(action);
                }
                onHoverEntered: action => {
                    if (gridHolder.dropNextHover) {
                        gridHolder.dropNextHover = false;
                        return;
                    }
                    gridHolder.hovered(action);
                }
                onHoverExited: () => {
                    return gridHolder.unhovered();
                }
            }
        }
    }
}
