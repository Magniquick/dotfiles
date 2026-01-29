/**
 * @module WorkspaceGroup
 * @description Grouped container for workspace modules
 *
 * Contains:
 * - WorkspacesModule (numbered workspaces, always visible)
 * - SpecialWorkspacesModule (special workspaces, in drawer)
 *
 * Uses DrawerGroup for expandable special workspaces.
 */
import ".."
import "../components"
import QtQuick

ModuleContainer {
    id: root

    property var screen

    backgroundColor: Config.barModuleBackground
    clip: true
    contentSpacing: 0
    marginLeft: 0
    marginRight: 0
    marginTop: Config.outerGaps
    minHeight: 0
    paddingBottom: 0
    paddingLeft: 0
    paddingRight: 0
    paddingTop: 0

    content: [
        DrawerGroup {
            duration: Config.motion.duration.medium

            alwaysContent: [
                WorkspacesModule {
                    screen: root.screen
                }
            ]
            drawerContent: [
                SpecialWorkspacesModule {
                    iconMap: ({
                            "magic": "",
                            "spotify": "",
                            "whatsapp": "󰖣"
                        })
                    screen: root.screen
        }
    ]

}
    ]

}
