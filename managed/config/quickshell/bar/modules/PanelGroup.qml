import ".."
import "../components"

ModuleContainer {
    id: root

    property var parentWindow

    paddingLeft: Config.groupPaddingX
    paddingRight: Config.groupPaddingX
    paddingTop: 0
    paddingBottom: 0
    marginTop: Config.moduleMarginTop
    marginRight: Config.groupEdgeMargin
    backgroundColor: Config.moduleBackground
    contentSpacing: 0
    content: [
        DrawerGroup {
            duration: Config.motion.duration.medium
            drawerLeft: true
            alwaysContent: [
                NotificationModule {
                    backgroundColor: "transparent"
                    marginLeft: 0
                    marginRight: 0
                    marginTop: 0
                    marginBottom: 0
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
