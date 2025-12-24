import ".."
import "../components"

ModuleContainer {
  paddingLeft: Config.groupPaddingX
  paddingRight: Config.groupPaddingX
  paddingTop: 0
  paddingBottom: 0
  marginTop: Config.moduleMarginTop
  backgroundColor: Config.moduleBackground
  contentSpacing: 0

  content: [
    NetworkModule {
      backgroundColor: "transparent"
      marginLeft: 0
      marginRight: 0
      marginTop: 0
      marginBottom: 0
    },
    BluetoothModule {
      backgroundColor: "transparent"
      marginLeft: 0
      marginRight: 0
      marginTop: 0
      marginBottom: 0
    }
  ]
}
