import ".."
import "../components"

ModuleContainer {
  id: root
  property var screen
  paddingLeft: 0
  paddingRight: 0
  paddingTop: 0
  paddingBottom: 0
  marginTop: Config.moduleMarginTop
  marginLeft: 0
  marginRight: 0
  backgroundColor: Config.moduleBackground
  contentSpacing: 0
  minHeight: 0

  content: [
    DrawerGroup {
      duration: Config.motion.duration.medium
      alwaysContent: [
        WorkspacesModule { screen: root.screen }
      ]
      drawerContent: [
        SpecialWorkspacesModule {
          screen: root.screen
          iconMap: ({
            "magic": "",
            "spotify": "",
            "whatsapp": "󰖣"
          })
        }
      ]
    }
  ]
}
