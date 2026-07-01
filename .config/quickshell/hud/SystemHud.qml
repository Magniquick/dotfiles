pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../bar" as Bar
import "../bar/components" as BarComponents

PanelWindow {
  id: root

  required property var targetScreen
  property bool exiting: false
  readonly property bool hudActive: Bar.HudService.active
  readonly property int transitionMs: Bar.Config.systemHud.transitionMs

  color: "transparent"
  visible: Bar.Config.systemHud.enabled && (root.hudActive || root.exiting)
  screen: root.targetScreen
  implicitWidth: Bar.Config.systemHud.width
  implicitHeight: Bar.Config.systemHud.height + Bar.Config.systemHud.bottomMargin
  exclusiveZone: 0

  WlrLayershell.namespace: "quickshell:system-hud"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  anchors {
    bottom: true
  }

  onHudActiveChanged: {
    if (root.hudActive) {
      root.exiting = false
      exitTimer.stop()
    } else {
      root.exiting = true
      exitTimer.restart()
    }
  }

  Timer {
    id: exitTimer

    interval: root.transitionMs
    repeat: false
    onTriggered: root.exiting = false
  }

  Rectangle {
    id: surface

    width: parent.width
    height: Bar.Config.systemHud.height
    color: Bar.Config.barPopupSurface
    opacity: root.hudActive ? 1 : 0
    radius: Bar.Config.shape.corner.md
    border.color: Qt.alpha(Bar.Config.color.outline_variant, 0.55)
    border.width: 1
    y: root.hudActive ? 0 : Bar.Config.space.md

    Behavior on opacity {
      NumberAnimation {
        duration: root.transitionMs
        easing.type: root.hudActive ? Easing.OutCubic : Easing.InCubic
      }
    }

    Behavior on y {
      NumberAnimation {
        duration: root.transitionMs
        easing.type: root.hudActive ? Easing.OutCubic : Easing.InCubic
      }
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Bar.Config.space.md
      anchors.rightMargin: Bar.Config.space.md
      spacing: Bar.Config.space.sm

      Text {
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: Bar.Config.systemHud.iconSize
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: Bar.HudService.muted ? Bar.Config.color.error : Bar.Config.color.primary
        font.family: Bar.Config.iconFontFamily
        font.pixelSize: Bar.Config.systemHud.iconSize
        text: Bar.HudService.icon
      }

      BarComponents.ProgressBar {
        Layout.alignment: Qt.AlignVCenter
        Layout.fillWidth: true
        Layout.preferredHeight: 8
        barHeight: 8
        fillColor: Bar.HudService.muted ? Bar.Config.color.error : Bar.Config.color.primary
        trackColor: Qt.alpha(Bar.Config.color.surface_variant, 0.68)
        value: Bar.HudService.value / 100
        visible: Bar.HudService.showProgress
      }

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        visible: !Bar.HudService.showProgress
      }

      Text {
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: Bar.HudService.showProgress ? 52 : 116
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter
        color: Bar.Config.color.on_surface
        elide: Text.ElideRight
        font.family: Bar.Config.fontFamily
        font.pixelSize: Bar.Config.type.titleMedium.size
        font.weight: Bar.Config.type.titleMedium.weight
        text: Bar.HudService.label
      }
    }
  }
}
