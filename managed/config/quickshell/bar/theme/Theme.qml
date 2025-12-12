pragma Singleton
import "../Colors.js" as RawColors
import QtQuick

QtObject {
  readonly property var colors: RawColors.palette

  readonly property int barHeight: 32
  readonly property int spacing: 4
  readonly property int radius: 18
  readonly property int groupPadX: 4
  readonly property int groupPadY: 6
  readonly property int modulePadX: 7
  readonly property int modulePadY: 6
  readonly property int topMargin: 5
  readonly property int edgeMargin: 5

  readonly property string fontFamily: "JetBrainsMono Nerd Font Propo"
  readonly property int fontSize: 14

  readonly property color background: colors.base
  readonly property color text: colors.text
}
