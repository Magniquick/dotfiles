pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../common/materialkit" as MK
import "../../common" as Common

MK.Card {
  id: root

  property string errorText: ""
  property bool busy: false

  signal submitted(string url, string label)
  signal dismissed

  type: MK.Enum.cardOutlined
  width: 360
  height: Math.min(420, contentColumn.implicitHeight + Common.Config.space.xl * 2)

  function focusPrimaryField() {
    urlInput.forceActiveFocus()
  }

  function clearForm() {
    urlInput.text = ""
    labelInput.text = ""
    root.errorText = ""
  }

  ColumnLayout {
    id: contentColumn
    anchors.fill: parent
    anchors.margins: Common.Config.space.lg
    spacing: Common.Config.space.md

    RowLayout {
      Layout.fillWidth: true
      spacing: Common.Config.space.sm

      Text {
        text: "\uf8fe"
        color: Common.Config.color.primary
        font.family: Common.Config.iconFontFamily
        font.pixelSize: 18
      }

      Text {
        text: qsTr("ADD MCP SERVER")
        color: Common.Config.color.primary
        font.family: Common.Config.fontFamily
        font.pixelSize: 12
        font.weight: Font.Black
      }

      Item {
        Layout.fillWidth: true
      }

      MK.ClickableSurface {
        id: closeButton
        Layout.preferredWidth: 26
        Layout.preferredHeight: 26
        radius: 13
        enabled: !root.busy
        backgroundColor: "transparent"
        hoverBackgroundColor: "transparent"
        pressedBackgroundColor: "transparent"
        rippleColor: Common.Config.color.error
        rippleStateOpacity: closeButton.hovered ? Common.Config.state.hoverOpacity : 0

        onClicked: root.dismissed()

        Text {
          anchors.centerIn: parent
          text: "\uf00d"
          color: closeButton.hovered ? Common.Config.color.error : Common.Config.color.on_surface_variant
          font.family: Common.Config.iconFontFamily
          font.pixelSize: 14
        }
      }
    }

    Text {
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      text: qsTr("Add a new HTTP MCP endpoint. URL is required. Label is optional. Tokens and custom headers can be added later in mcp_servers.json.")
      color: Common.Config.color.on_surface_variant
      font.family: Common.Config.fontFamily
      font.pixelSize: Common.Config.type.bodySmall.size
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Common.Config.space.xs

      Text {
        text: qsTr("Endpoint URL")
        color: Common.Config.color.on_surface
        font.family: Common.Config.fontFamily
        font.pixelSize: Common.Config.type.labelMedium.size
        font.weight: Font.DemiBold
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 42
        radius: Common.Config.shape.corner.md
        color: Common.Config.color.surface
        border.width: 1
        border.color: Qt.alpha(Common.Config.color.on_surface, 0.12)

        MK.TextField {
          id: urlInput
          anchors.fill: parent
          anchors.leftMargin: Common.Config.space.md
          anchors.rightMargin: Common.Config.space.md
          placeholderText: qsTr("https://example.com/mcp")
          background: null
          color: Common.Config.color.on_surface
          placeholderTextColor: Qt.alpha(Common.Config.color.on_surface_variant, 0.7)
          font.family: Common.Config.fontFamily
          font.pixelSize: 13
          enabled: !root.busy
          selectByMouse: true
          onTextEdited: root.errorText = ""
          Keys.onReturnPressed: root.submitted(text, labelInput.text)
          Keys.onEnterPressed: root.submitted(text, labelInput.text)
        }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Common.Config.space.xs

      Text {
        text: qsTr("Label (optional)")
        color: Common.Config.color.on_surface
        font.family: Common.Config.fontFamily
        font.pixelSize: Common.Config.type.labelMedium.size
        font.weight: Font.DemiBold
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 42
        radius: Common.Config.shape.corner.md
        color: Common.Config.color.surface
        border.width: 1
        border.color: Qt.alpha(Common.Config.color.on_surface, 0.12)

        MK.TextField {
          id: labelInput
          anchors.fill: parent
          anchors.leftMargin: Common.Config.space.md
          anchors.rightMargin: Common.Config.space.md
          placeholderText: qsTr("Optional display label")
          background: null
          color: Common.Config.color.on_surface
          placeholderTextColor: Qt.alpha(Common.Config.color.on_surface_variant, 0.7)
          font.family: Common.Config.fontFamily
          font.pixelSize: 13
          enabled: !root.busy
          selectByMouse: true
          onTextEdited: root.errorText = ""
          Keys.onReturnPressed: root.submitted(urlInput.text, text)
          Keys.onEnterPressed: root.submitted(urlInput.text, text)
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      visible: root.errorText.length > 0
      radius: Common.Config.shape.corner.md
      color: Qt.alpha(Common.Config.color.error, 0.12)
      border.width: 1
      border.color: Qt.alpha(Common.Config.color.error, 0.25)
      implicitHeight: errorLabel.implicitHeight + Common.Config.space.md * 2

      Text {
        id: errorLabel
        anchors.fill: parent
        anchors.margins: Common.Config.space.md
        wrapMode: Text.WordWrap
        text: root.errorText
        color: Common.Config.color.error
        font.family: Common.Config.fontFamily
        font.pixelSize: Common.Config.type.bodySmall.size
      }
    }

    Item {
      Layout.fillHeight: true
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Common.Config.space.sm

      MK.ClickableSurface {
        id: cancelButton
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        radius: Common.Config.shape.corner.md
        enabled: !root.busy
        backgroundColor: Common.Config.color.surface
        hoverBackgroundColor: Common.Config.color.surface
        pressedBackgroundColor: Common.Config.color.surface
        border.width: 1
        border.color: Qt.alpha(Common.Config.color.on_surface, 0.14)
        rippleColor: Common.Config.color.on_surface
        rippleStateOpacity: cancelButton.hovered ? Common.Config.state.hoverOpacity : 0

        onClicked: root.dismissed()

        Text {
          anchors.centerIn: parent
          text: qsTr("Cancel")
          color: Common.Config.color.on_surface_variant
          font.family: Common.Config.fontFamily
          font.pixelSize: Common.Config.type.labelLarge.size
          font.weight: Font.DemiBold
        }
      }

      MK.ClickableSurface {
        id: submitButton
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        radius: Common.Config.shape.corner.md
        enabled: !root.busy
        backgroundColor: root.busy ? Qt.alpha(Common.Config.color.primary, 0.5) : Common.Config.color.primary
        disabledOpacity: 1
        hoverBackgroundColor: backgroundColor
        pressedBackgroundColor: backgroundColor
        rippleColor: Common.Config.color.on_primary
        rippleStateOpacity: submitButton.hovered && !root.busy ? Common.Config.state.hoverOpacity : 0

        onClicked: root.submitted(urlInput.text, labelInput.text)

        Text {
          anchors.centerIn: parent
          text: root.busy ? qsTr("Saving...") : qsTr("Add Server")
          color: Common.Config.color.on_primary
          font.family: Common.Config.fontFamily
          font.pixelSize: Common.Config.type.labelLarge.size
          font.weight: Font.Black
        }
      }
    }
  }
}
