import ".."
import "../components"

ModuleContainer {
  paddingLeft: Config.groupPaddingX
  paddingRight: Config.groupPaddingX
  paddingTop: 0
  paddingBottom: 0
  marginTop: Config.moduleMarginTop
  marginLeft: Config.groupEdgeMargin
  marginRight: 0
  backgroundColor: Config.moduleBackground
  contentSpacing: 0

  content: [
    DrawerGroup {
      duration: Config.motion.duration.medium
      alwaysContent: [
        ArchIconModule {
          backgroundColor: "transparent"
          marginLeft: 0
          marginRight: 0
          marginTop: 0
          marginBottom: 0
        },
        SystemdFailedModule {
          backgroundColor: "transparent"
          marginLeft: 0
          marginRight: 0
          marginTop: 0
          marginBottom: 0
        }
      ]
      drawerContent: [
        UpdatesModule {
          backgroundColor: "transparent"
          marginLeft: 0
          marginRight: 0
          marginTop: 0
          marginBottom: 0
        },
        PowerProfilesModule {
          backgroundColor: "transparent"
          marginLeft: 0
          marginRight: 0
          marginTop: 0
          marginBottom: 0
        }
      ]
    }
  ]
}
