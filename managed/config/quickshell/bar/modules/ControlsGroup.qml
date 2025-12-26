import ".."
import "../components"
import QtQuick

ModuleContainer {
    paddingLeft: Config.groupPaddingX
    paddingRight: Config.groupPaddingX
    paddingTop: 0
    paddingBottom: 0
    marginTop: Config.moduleMarginTop
    backgroundColor: Config.moduleBackground
    contentSpacing: 0
    content: [
        WireplumberModule {
            backgroundColor: "transparent"
            marginLeft: 0
            marginRight: 0
            marginTop: 0
            marginBottom: 0
        },
        BacklightModule {
            backgroundColor: "transparent"
            marginLeft: 0
            marginRight: 0
            marginTop: 0
            marginBottom: 0
        },
        Loader {
            active: Config.enablePrivacyModule
            sourceComponent: privacyComponent
            visible: active
        }
    ]

    Component {
        id: privacyComponent

        PrivacyModule {
            backgroundColor: "transparent"
            marginLeft: 0
            marginRight: 0
            marginTop: 0
            marginBottom: 0
        }
    }
}
