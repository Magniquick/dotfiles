import QtQuick
import QtQuick.Layouts
import "."
import "headers"

Item {
  id: root

  property int currentDesign: 0
  readonly property string mockTitle: "Battery"

  implicitWidth: mainLayout.implicitWidth
  implicitHeight: mainLayout.implicitHeight

  ColumnLayout {
    id: mainLayout
    spacing: Config.space.lg

    // Design switcher buttons
    RowLayout {
      Layout.alignment: Qt.AlignHCenter
      spacing: Config.space.xs

      Repeater {
        model: ["Current", "Compact", "Pill", "Bar", "Minimal"]

        delegate: Rectangle {
          required property string modelData
          required property int index

          implicitWidth: buttonLabel.implicitWidth + Config.space.md * 2
          implicitHeight: Config.space.xl
          radius: height / 2
          color: root.currentDesign === index ? Config.color.primary : Config.color.surface_container_high
          border.color: root.currentDesign === index ? Config.color.primary : Config.color.outline_variant
          border.width: 1

          Text {
            id: buttonLabel
            anchors.centerIn: parent
            text: modelData
            color: root.currentDesign === index ? Config.color.on_primary : Config.color.on_surface
            font.family: Config.fontFamily
            font.pixelSize: Config.type.labelSmall.size
            font.weight: Config.type.labelSmall.weight
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.currentDesign = index
          }

          Behavior on color {
            ColorAnimation { duration: Config.motion.duration.shortMs }
          }
        }
      }
    }

    // Tooltip container
    Rectangle {
      Layout.alignment: Qt.AlignHCenter
      Layout.preferredWidth: 240
      implicitHeight: tooltipContent.implicitHeight + Config.tooltipPadding * 2
      color: Config.barPopupSurface
      radius: Config.tooltipRadius
      border.color: Config.barPopupBorderColor
      border.width: Config.tooltipBorderWidth

      ColumnLayout {
        id: tooltipContent
        anchors.fill: parent
        anchors.margins: Config.tooltipPadding
        spacing: Config.space.sm

        // Header row - switches based on currentDesign
        Loader {
          Layout.fillWidth: true
          sourceComponent: {
            switch (root.currentDesign) {
              case 0: return currentComponent
              case 1: return compactComponent
              case 2: return pillComponent
              case 3: return barComponent
              case 4: return minimalComponent
              default: return currentComponent
            }
          }
        }

        // Mock tooltip content
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 60
          color: Config.color.surface_container_low
          radius: Config.shape.corner.xs

          Text {
            anchors.centerIn: parent
            text: "(content)"
            color: Config.color.on_surface_variant
            font.family: Config.fontFamily
            font.pixelSize: Config.type.labelSmall.size
            opacity: 0.4
          }
        }
      }
    }

    // Instructions
    Text {
      Layout.alignment: Qt.AlignHCenter
      text: "Esc/Q to exit"
      color: Config.color.on_surface_variant
      font.family: Config.fontFamily
      font.pixelSize: Config.type.labelSmall.size
      opacity: 0.5
    }
  }

  Component {
    id: currentComponent
    CurrentHeader { title: root.mockTitle }
  }

  Component {
    id: compactComponent
    CompactLabelHeader { title: root.mockTitle }
  }

  Component {
    id: pillComponent
    PillHeader { title: root.mockTitle }
  }

  Component {
    id: barComponent
    AccentBarHeader { title: root.mockTitle }
  }

  Component {
    id: minimalComponent
    MinimalHeader { title: root.mockTitle }
  }
}
