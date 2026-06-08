pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../common" as Common
import "../../common/materialkit" as MK

Item {
  id: root

  property var tabs: []
  property int currentIndex: 0
  property string statusText: ""
  property string connectionStatus: "online"

  signal tabSelected(int index)
  signal refreshRequested

  implicitWidth: tabRow.width
  implicitHeight: tabRow.height

  RowLayout {
    id: tabRow
    anchors.centerIn: parent
    spacing: 48

    Repeater {
      model: root.tabs

      Item {
        id: tabItem
        required property int index
        required property var modelData

        readonly property bool isActive: root.currentIndex === tabItem.index
        property bool isHovered: false

        Layout.preferredHeight: 48
        implicitWidth: tabContent.width
        clip: true

        Column {
          id: tabContent
          anchors.centerIn: parent
          spacing: Common.Config.space.md

          RowLayout {
            spacing: Common.Config.space.sm

            Text {
              text: tabItem.modelData.icon || ""
              color: tabItem.isActive ? tabItem.modelData.accent : (tabItem.isHovered ? Common.Config.color.on_surface : Common.Config.color.on_surface_variant)
              font.family: Common.Config.iconFontFamily
              font.pixelSize: 16
              visible: (tabItem.modelData.icon || "").length > 0
              opacity: tabItem.isActive ? 1.0 : (tabItem.isHovered ? 0.8 : 0.5)

              Behavior on color {
                ColorAnimation {
                  duration: 200
                }
              }
              Behavior on opacity {
                NumberAnimation {
                  duration: 200
                }
              }
            }

            Text {
              text: tabItem.modelData.label || ""
              color: tabItem.isActive ? tabItem.modelData.accent : (tabItem.isHovered ? Common.Config.color.on_surface : Common.Config.color.on_surface_variant)
              font.family: Common.Config.fontFamily
              font.pixelSize: 11
              font.weight: Font.Black
              font.capitalization: Font.AllUppercase
              opacity: tabItem.isActive ? 1.0 : (tabItem.isHovered ? 0.8 : 0.5)

              Behavior on color {
                ColorAnimation {
                  duration: 200
                }
              }
              Behavior on opacity {
                NumberAnimation {
                  duration: 200
                }
              }
            }
          }

          // Underline indicator
          Rectangle {
            width: tabContent.width
            height: 4
            radius: 2
            color: tabItem.isActive ? tabItem.modelData.accent : "transparent"
            anchors.horizontalCenter: parent.horizontalCenter

            Behavior on color {
              ColorAnimation {
                duration: 250
                easing.type: Easing.OutCubic
              }
            }
          }
        }

        MK.ClickableSurface {
          anchors.fill: parent
          backgroundColor: "transparent"
          hoverBackgroundColor: "transparent"
          pressedBackgroundColor: "transparent"
          radius: 0
          rippleColor: tabItem.modelData.accent
          rippleStateOpacity: 0

          onClicked: root.tabSelected(tabItem.index)
          onHoveredChanged: tabItem.isHovered = hovered
        }
      }
    }
  }
}
