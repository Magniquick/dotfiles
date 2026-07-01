pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."
import "../../common/materialkit" as MK

ColumnLayout {
  id: root

  readonly property bool showSystem: root.systemCount > 0
  readonly property bool showUser: root.userCount > 0
  readonly property int systemCount: root.modelCount(root.systemUnits)
  property var systemUnits: []
  readonly property int totalCount: root.systemCount + root.userCount
  readonly property int userCount: root.modelCount(root.userUnits)
  property var userUnits: []

  function modelCount(model) {
    if (model && typeof model.length === "number")
      return model.length
    if (model && model.values && typeof model.values.length === "number")
      return model.values.length
    return 0
  }

  function formatStatus(unitObj) {
    const active = unitObj && unitObj.active ? String(unitObj.active) : ""
    const sub = unitObj && unitObj.sub ? String(unitObj.sub) : ""
    if (active !== "" && sub !== "")
      return active === sub ? active : (active + " • " + sub)
    return active !== "" ? active : sub
  }

  Layout.fillWidth: true
  spacing: Config.space.md

  RowLayout {
    Layout.fillWidth: true
    spacing: Config.space.md

    Item {
      Layout.preferredHeight: Config.space.xxl * 2
      Layout.preferredWidth: Config.space.xxl * 2
      implicitHeight: Config.space.xxl * 2
      implicitWidth: Config.space.xxl * 2

      Text {
        anchors.centerIn: parent
        color: Config.color.error
        font.family: Config.iconFontFamily
        font.pixelSize: Config.type.headlineLarge.size
        text: ""
      }
    }
    ColumnLayout {
      spacing: Config.space.none

      Text {
        Layout.fillWidth: true
        color: Config.color.on_surface
        elide: Text.ElideRight
        font.family: Config.fontFamily
        font.pixelSize: Config.type.headlineMedium.size
        font.weight: Font.Bold
        text: root.totalCount + (root.totalCount === 1 ? " Failed unit" : " Failed units")
      }
      Text {
        Layout.fillWidth: true
        color: Config.color.on_surface_variant
        elide: Text.ElideRight
        font.family: Config.fontFamily
        font.pixelSize: Config.type.labelMedium.size
        text: "system: " + root.systemCount + " • user: " + root.userCount
      }
    }
    Item {
      Layout.fillWidth: true
    }
  }
  TooltipCard {
    Layout.fillWidth: true
    // Match the "inner container" styling used by ToDo tooltip.
    backgroundColor: Config.color.on_secondary_fixed_variant
    borderColor: Config.color.outline_variant
    outlined: true

    content: [
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Config.space.sm

        MK.Flickable {
          id: listFlick

          Layout.fillWidth: true
          contentHeight: listColumn.implicitHeight
          implicitHeight: Math.min(contentHeight, 260)

          Column {
            id: listColumn

            spacing: Config.space.sm
            width: listFlick.width

            Text {
              color: Config.color.on_surface_variant
              font.family: Config.fontFamily
              font.pixelSize: Config.type.bodySmall.size
              text: "No failed units."
              visible: root.totalCount === 0
            }
            Column {
              spacing: Config.space.sm
              visible: root.showSystem
              width: listColumn.width

              Text {
                color: Config.color.primary
                font.family: Config.fontFamily
                font.letterSpacing: 1.5
                font.pixelSize: Config.type.labelSmall.size
                font.weight: Font.Black
                text: "SYSTEM"
              }
              Repeater {
                model: root.systemUnits

                delegate: RowLayout {
                  id: unitRow
                  required property var modelData
                  readonly property int stripeWidth: Config.spaceHalfXs

                  spacing: Config.space.md
                  width: listColumn.width

                  Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredHeight: Config.type.bodySmall.line + unitRow.stripeWidth
                    color: Config.color.error
                    opacity: 0.8
                    radius: Config.shape.corner.xs
                    Layout.preferredWidth: unitRow.stripeWidth
                    implicitWidth: unitRow.stripeWidth
                  }
                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Config.space.none

                    Text {
                      Layout.fillWidth: true
                      color: Config.color.error
                      elide: Text.ElideRight
                      font.family: Config.fontFamily
                      font.pixelSize: Config.type.bodyMedium.size
                      font.weight: Font.Medium
                      text: unitRow.modelData.unit || ""
                    }
                    Text {
                      Layout.fillWidth: true
                      color: Config.color.on_surface_variant
                      elide: Text.ElideRight
                      font.family: Config.fontFamily
                      font.pixelSize: Config.type.bodySmall.size
                      maximumLineCount: 2
                      text: unitRow.modelData.description || ""
                      visible: text !== ""
                      wrapMode: Text.WordWrap
                    }
                  }
                  Text {
                    color: Config.color.on_surface_variant
                    elide: Text.ElideRight
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.labelSmall.size
                    opacity: 0.8
                    text: root.formatStatus(unitRow.modelData)
                    visible: text !== ""
                  }
                }
              }
            }
            Rectangle {
              color: Config.color.outline
              height: 1
              opacity: 0.18
              visible: root.showSystem && root.showUser
              width: listColumn.width
            }
            Column {
              spacing: Config.space.sm
              visible: root.showUser
              width: listColumn.width

              Text {
                color: Config.color.primary
                font.family: Config.fontFamily
                font.letterSpacing: 1.5
                font.pixelSize: Config.type.labelSmall.size
                font.weight: Font.Black
                text: "USER"
              }
              Repeater {
                model: root.userUnits

                delegate: RowLayout {
                  id: userRow
                  required property var modelData
                  readonly property int stripeWidth: Config.spaceHalfXs

                  spacing: Config.space.md
                  width: listColumn.width

                  Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredHeight: Config.type.bodySmall.line + userRow.stripeWidth
                    color: Config.color.error
                    opacity: 0.8
                    radius: Config.shape.corner.xs
                    Layout.preferredWidth: userRow.stripeWidth
                    implicitWidth: userRow.stripeWidth
                  }
                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Config.space.none

                    Text {
                      Layout.fillWidth: true
                      color: Config.color.error
                      elide: Text.ElideRight
                      font.family: Config.fontFamily
                      font.pixelSize: Config.type.bodyMedium.size
                      font.weight: Font.Medium
                      text: userRow.modelData.unit || ""
                    }
                    Text {
                      Layout.fillWidth: true
                      color: Config.color.on_surface_variant
                      elide: Text.ElideRight
                      font.family: Config.fontFamily
                      font.pixelSize: Config.type.bodySmall.size
                      maximumLineCount: 2
                      text: userRow.modelData.description || ""
                      visible: text !== ""
                      wrapMode: Text.WordWrap
                    }
                  }
                  Text {
                    color: Config.color.on_surface_variant
                    elide: Text.ElideRight
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.labelSmall.size
                    opacity: 0.8
                    text: root.formatStatus(userRow.modelData)
                    visible: text !== ""
                  }
                }
              }
            }
          }
        }
      }
    ]
  }
}
