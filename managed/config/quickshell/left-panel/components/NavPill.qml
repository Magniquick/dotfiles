import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../common" as Common

Item {
  id: root

  property var tabs: []
  property int currentIndex: 0
  property string statusText: ""
  property string connectionStatus: "online"

  signal tabSelected(int index)
  signal refreshRequested()

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

          readonly property bool isActive: root.currentIndex === index
          property bool isHovered: false

          Layout.preferredHeight: 48
          implicitWidth: tabContent.width

          Column {
            id: tabContent
            anchors.centerIn: parent
            spacing: Common.Config.space.md

            RowLayout {
              spacing: Common.Config.space.sm

              Text {
                text: modelData.icon || ""
                color: tabItem.isActive ? modelData.accent : (tabItem.isHovered ? Common.Config.textColor : Common.Config.textMuted)
                font.family: Common.Config.iconFontFamily
                font.pixelSize: 16
                visible: (modelData.icon || "").length > 0
                opacity: tabItem.isActive ? 1.0 : (tabItem.isHovered ? 0.8 : 0.5)

                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on opacity { NumberAnimation { duration: 200 } }
              }

              Text {
                text: modelData.label || ""
                color: tabItem.isActive ? modelData.accent : (tabItem.isHovered ? Common.Config.textColor : Common.Config.textMuted)
                font.family: Common.Config.fontFamily
                font.pixelSize: 11
                font.weight: Font.Black
                font.letterSpacing: 1.8
                font.capitalization: Font.AllUppercase
                opacity: tabItem.isActive ? 1.0 : (tabItem.isHovered ? 0.8 : 0.5)

                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on opacity { NumberAnimation { duration: 200 } }
              }
            }

            // Underline indicator
            Rectangle {
              width: tabContent.width
              height: 4
              radius: 2
              color: tabItem.isActive ? modelData.accent : "transparent"
              anchors.horizontalCenter: parent.horizontalCenter

              Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: root.tabSelected(tabItem.index)
            onEntered: tabItem.isHovered = true
            onExited: tabItem.isHovered = false
          }
        }
      }
  }
}
