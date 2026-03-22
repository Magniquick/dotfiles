pragma Singleton

import QtQuick

QtObject {
  component FontToken: QtObject {
    property string family: "Sans"
  }

  component FontConfig: QtObject {
    property FontToken default_font: FontToken {}
    property string icon_family: "Sans"
    property string icon_fill_family: "Sans"
  }

  readonly property QtObject elevation: QtObject {
    readonly property int level0: 0
    readonly property int level1: 1
    readonly property int level2: 2
    readonly property int level3: 3
  }

  // Compatibility surface for previous MaterialBridge-style writes.
  readonly property QtObject color: QtObject {
    property bool useSysColorSM: false
    property bool useSysAccentColor: false
    property color accentColor: "#000000"
  }

  readonly property FontConfig font: FontConfig {}
}
