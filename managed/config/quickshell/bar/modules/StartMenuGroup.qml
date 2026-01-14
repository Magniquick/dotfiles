/**
 * @module StartMenuGroup
 * @description Left-side group with system info and status modules
 *
 * Contains:
 * - ArchIconModule (always visible, opens powermenu)
 * - SystemdFailedModule (always visible, shows failed units)
 * - UpdatesModule (in drawer, shows pending updates)
 * - ToDoModule (in drawer, shows tasks)
 *
 * Uses DrawerGroup for expandable updates/tasks section.
 */
import ".."
import "../components"

ModuleContainer {
    backgroundColor: Config.moduleBackground
    contentSpacing: 0
    marginLeft: Config.groupEdgeMargin
    marginRight: 0
    marginTop: Config.moduleMarginTop
    paddingBottom: 0
    paddingLeft: Config.groupPaddingX
    paddingRight: Config.groupPaddingX
    paddingTop: 0

    content: [
        DrawerGroup {
            duration: Config.motion.duration.medium

            alwaysContent: [
                ArchIconModule {
                    backgroundColor: "transparent"
                    marginBottom: 0
                    marginLeft: 0
                    marginRight: 0
                    marginTop: 0
                },
                SystemdFailedModule {
                    backgroundColor: "transparent"
                    marginBottom: 0
                    marginLeft: 0
                    marginRight: 0
                    marginTop: 0
                }
            ]
            drawerContent: [
                UpdatesModule {
                    backgroundColor: "transparent"
                    marginBottom: 0
                    marginLeft: 0
                    marginRight: 0
                    marginTop: 0
                }
            ]
        }
    ]
}
