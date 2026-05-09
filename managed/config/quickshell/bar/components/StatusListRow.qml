pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."
import "../../common/materialkit" as MK

Rectangle {
  id: root

  property string title: ""
  property string subtitle: ""
  property string leadingIcon: ""
  property string trailingIcon: ""
  property string badgeText: ""
  property color badgeColor: Qt.alpha(Config.color.tertiary, 0.9)
  property color badgeTextColor: Config.color.on_tertiary
  property bool active: false
  property bool interactive: true
  property int rowHeight: 44
  property real pressX: width / 2
  property real pressY: height / 2
  signal clicked

  Layout.fillWidth: true
  Layout.preferredHeight: rowHeight
  width: ListView.view ? ListView.view.width : (parent ? parent.width : implicitWidth)
  height: rowHeight
  radius: Config.shape.corner.md
  color: rowMouseArea.containsMouse
    ? Qt.alpha(Config.color.surface_variant, 0.45)
    : (active ? Qt.alpha(Config.color.primary_container, 0.45) : Config.color.surface_container_high)

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Config.space.sm
    anchors.rightMargin: Config.space.sm
    spacing: Config.space.sm

    Rectangle {
      Layout.alignment: Qt.AlignVCenter
      Layout.preferredHeight: 28
      Layout.preferredWidth: 28
      color: root.active ? Qt.alpha(Config.color.primary, 0.75) : Config.color.surface_variant
      radius: width / 2

      Text {
        anchors.fill: parent
        color: root.active ? Config.color.on_primary : Config.color.on_surface
        font.family: Config.iconFontFamily
        font.pixelSize: Config.type.labelLarge.size
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.leadingIcon
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.minimumWidth: 0
      spacing: Config.space.none

      Text {
        Layout.fillWidth: true
        color: root.active ? Config.color.on_primary_container : Config.color.on_surface
        elide: Text.ElideRight
        font.family: Config.fontFamily
        font.pixelSize: Config.type.bodyLarge.size
        font.weight: Config.type.bodyLarge.weight
        font.variableAxes: Config.fontVariableAxes(Config.type.bodyLarge.size, Config.type.bodyLarge.weight)
        text: root.title
      }

      Text {
        Layout.fillWidth: true
        color: Config.color.on_surface_variant
        elide: Text.ElideRight
        font.family: Config.fontFamily
        font.pixelSize: Config.type.labelMedium.size
        font.variableAxes: Config.fontVariableAxes(Config.type.labelMedium.size, Font.Normal)
        text: root.subtitle
        visible: root.subtitle.length > 0
      }
    }

    Rectangle {
      Layout.alignment: Qt.AlignVCenter
      Layout.preferredHeight: badgeLabel.implicitHeight + Config.spaceHalfXs
      Layout.preferredWidth: badgeLabel.implicitWidth + Config.space.sm
      color: root.badgeColor
      radius: Config.shape.corner.sm
      visible: root.badgeText.length > 0

      Text {
        id: badgeLabel

        anchors.centerIn: parent
        color: root.badgeTextColor
        font.family: Config.fontFamily
        font.pixelSize: Config.type.labelSmall.size
        font.weight: Font.Bold
        font.variableAxes: Config.fontVariableAxes(Config.type.labelSmall.size, Font.Bold)
        text: root.badgeText
      }
    }

    Text {
      Layout.alignment: Qt.AlignVCenter
      color: Config.color.on_surface_variant
      font.family: Config.iconFontFamily
      font.pixelSize: Config.type.labelLarge.size
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: root.trailingIcon
      visible: root.trailingIcon.length > 0
    }
  }

  MK.HybridRipple {
    anchors.fill: parent
    color: root.active ? Config.color.on_primary_container : Config.color.on_surface
    pressX: root.pressX
    pressY: root.pressY
    pressed: rowMouseArea.pressed
    radius: parent.radius
    stateLayerEnabled: false
    stateOpacity: 0
  }

  MouseArea {
    id: rowMouseArea

    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: root.interactive
    cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
    onPressed: function(mouse) {
      root.pressX = mouse.x;
      root.pressY = mouse.y;
    }
  }
}
