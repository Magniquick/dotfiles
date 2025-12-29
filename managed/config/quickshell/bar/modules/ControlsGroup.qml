import ".."
import "../components"
import QtQuick

ModuleContainer {
    backgroundColor: Config.moduleBackground
    contentSpacing: 0
    marginTop: Config.moduleMarginTop
    paddingBottom: 0
    paddingLeft: Config.groupPaddingX
    paddingRight: Config.groupPaddingX
    paddingTop: 0

    content: [
        WireplumberModule {
            backgroundColor: "transparent"
            marginBottom: 0
            marginLeft: 0
            marginRight: 0
            marginTop: 0
        },
        BacklightModule {
            backgroundColor: "transparent"
            marginBottom: 0
            marginLeft: 0
            marginRight: 0
            marginTop: 0
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
            marginBottom: 0
            marginLeft: 0
            marginRight: 0
            marginTop: 0
        }
    }
}
