import ".."
import "../components"

ModuleContainer {
    id: root

    property var screen

    backgroundColor: Config.moduleBackground
    contentSpacing: 0
    marginLeft: 0
    marginRight: 0
    marginTop: Config.moduleMarginTop
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
