import ".."
import "../components"

ModuleContainer {
    backgroundColor: Config.moduleBackground
    contentSpacing: 0
    marginTop: Config.moduleMarginTop
    paddingBottom: 0
    paddingLeft: Config.groupPaddingX
    paddingRight: Config.groupPaddingX
    paddingTop: 0

    content: [
        NetworkModule {
            backgroundColor: "transparent"
            marginBottom: 0
            marginLeft: 0
            marginRight: 0
            marginTop: 0
        },
        BluetoothModule {
            backgroundColor: "transparent"
            marginBottom: 0
            marginLeft: 0
            marginRight: 0
            marginTop: 0
        }
    ]
}
