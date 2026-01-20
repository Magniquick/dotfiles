import QtQuick
import QtQuick.Layouts
import "../common" as Common

Item {
  id: root
  property string title: ""
  property string value: ""
  property string icon: ""
  property string subtext: ""
  property color accent: Common.Config.primary

  implicitHeight: 80
  Layout.fillWidth: true

  Rectangle {
    anchors.fill: parent
    radius: Common.Config.shape.corner.lg
    color: "transparent"
    border.width: 1
    border.color: Qt.alpha(Common.Config.textColor, 0.1)
    clip: true

    RowLayout {
      anchors.fill: parent
      anchors.margins: Common.Config.space.sm
      spacing: Common.Config.space.sm

      // Icon
      Rectangle {
        Layout.alignment: Qt.AlignVCenter
        width: 36
        height: 36
        radius: Common.Config.shape.corner.sm
        color: Qt.alpha(Common.Config.textColor, 0.05)

        Text {
          anchors.centerIn: parent
          text: root.icon
          color: root.accent
          font.family: Common.Config.iconFontFamily
          font.pixelSize: 16
        }
      }

      // Text content
      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 0

        Item { Layout.fillHeight: true }

        // Value
        Text {
          Layout.fillWidth: true
          text: root.value
          color: Common.Config.textColor
          font.family: Common.Config.fontFamily
          font.pixelSize: 16
          font.weight: Font.Bold
          elide: Text.ElideRight
        }

        // Label
        Text {
          Layout.fillWidth: true
          text: root.title
          color: Common.Config.textMuted
          font.family: Common.Config.fontFamily
          font.pixelSize: 9
          font.weight: Font.Bold
          font.letterSpacing: 1.5
          font.capitalization: Font.AllUppercase
          opacity: 0.5
          elide: Text.ElideRight
        }

        // Subtext
        Text {
          Layout.fillWidth: true
          visible: root.subtext !== ""
          text: root.subtext
          color: Common.Config.textMuted
          font.family: Common.Config.fontFamily
          font.pixelSize: 8
          opacity: 0.3
          elide: Text.ElideRight
        }

        Item { Layout.fillHeight: true }
      }
    }
  }
}
