/**
 * @module PanelGroup
 * @description Right-side panel group with notifications and system tray
 *
 * Contains:
 * - NotificationModule (always visible)
 * - TrayModule (in drawer, expands on hover)
 *
 * Uses DrawerGroup for expandable tray section.
 */
import ".."
import "../components"

ModuleContainer {
    id: root

    property var parentWindow

    backgroundColor: Config.moduleBackground
    contentSpacing: 0
    marginRight: Config.groupEdgeMargin
    marginTop: Config.outerGaps
    paddingBottom: 0
    paddingLeft: Config.groupPaddingX
    paddingRight: Config.groupPaddingX
    paddingTop: 0

    content: [
        DrawerGroup {
            drawerLeft: true
            duration: Config.motion.duration.medium

            alwaysContent: [
                NotificationModule {
                    backgroundColor: "transparent"
                    marginBottom: 0
                    marginLeft: 0
                    marginRight: 0
                    marginTop: 0
                }
            ]
            drawerContent: [
                TrayModule {
                    parentWindow: root.parentWindow
                }
            ]
        }
    ]
}
