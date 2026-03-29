pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.bar

ComboBox {
  id: root

  implicitHeight: 40
  leftPadding: Config.space.sm
  rightPadding: Config.space.xl + Config.space.sm

  delegate: ItemDelegate {
    required property var modelData
    required property int index

    width: ListView.view ? ListView.view.width : root.width
    highlighted: root.highlightedIndex === index

    background: Rectangle {
      radius: Config.shape.corner.sm
      color: parent.highlighted
        ? Qt.tint(Config.color.primary_container, Qt.alpha(Config.color.primary, 0.18))
        : (delegateArea.containsMouse ? Qt.alpha(Config.color.surface_container_high, 0.8) : "transparent")
    }

    contentItem: Text {
      color: parent.highlighted ? Config.color.on_surface : Config.color.on_surface
      elide: Text.ElideRight
      font.family: Config.fontFamily
      font.pixelSize: Config.type.bodyMedium.size
      text: String(modelData)
      verticalAlignment: Text.AlignVCenter
    }

    MouseArea {
      id: delegateArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }
  }

  indicator: Text {
    anchors.right: parent.right
    anchors.rightMargin: Config.space.sm
    anchors.verticalCenter: parent.verticalCenter
    color: Config.color.on_surface_variant
    font.family: Config.iconFontFamily
    font.pixelSize: Config.type.labelLarge.size
    renderType: Text.NativeRendering
    text: "󰄼"
    rotation: root.popup.visible ? 90 : 0

    Behavior on rotation {
      NumberAnimation {
        duration: Config.motion.duration.shortMs
        easing.type: Config.motion.easing.standard
      }
    }
  }

  contentItem: Text {
    color: Config.color.on_surface
    elide: Text.ElideRight
    font.family: Config.fontFamily
    font.pixelSize: Config.type.bodyMedium.size
    leftPadding: 0
    rightPadding: 0
    text: root.displayText
    verticalAlignment: Text.AlignVCenter
  }

  background: Rectangle {
    radius: Config.shape.corner.sm
    color: Qt.tint(Config.barPopupSurface, Qt.alpha(Config.color.surface_container_high, 0.9))
    border.width: root.visualFocus ? 1.5 : 1
    border.color: root.visualFocus ? Config.color.primary : Qt.alpha(Config.color.outline_variant, 0.75)
  }

  popup: Popup {
    y: root.height + Config.space.xs
    width: root.width
    padding: Config.space.xs
    implicitHeight: Math.min(contentItem.implicitHeight + Config.space.sm * 2, 280)

    background: Rectangle {
      radius: Config.shape.corner.md
      color: Config.barPopupSurface
      border.width: 1
      border.color: Qt.alpha(Config.color.outline_variant, 0.85)
    }

    contentItem: ListView {
      clip: true
      implicitHeight: contentHeight
      model: root.popup.visible ? root.delegateModel : null
      currentIndex: root.highlightedIndex
      ScrollIndicator.vertical: ScrollIndicator {}
    }
  }
}
