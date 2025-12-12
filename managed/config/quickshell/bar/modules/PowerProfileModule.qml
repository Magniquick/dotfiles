import QtQuick
import QtQuick.Controls
import QtQml
import "./Label.qml"
import "../theme"

Item {
  id: root
  property string profileIcon: "󰾅"
  property string driver: ""
  property string tooltipText: ""
  property var powerProfiles: null
  property bool available: false

  implicitHeight: label.implicitHeight
  implicitWidth: label.implicitWidth
  visible: available

  function updateIcon() {
    if (!powerProfiles) {
      profileIcon = "󰾅";
      driver = "";
      tooltipText = "";
      return;
    }
    const prof = powerProfiles.profile;
    const asString = prof !== undefined && prof !== null ? prof.toString() : "";
    if (asString.indexOf("Performance") !== -1 || prof === 2) {
      profileIcon = "";
    } else if (asString.indexOf("PowerSaver") !== -1 || prof === 0) {
      profileIcon = "󰾆";
    } else {
      profileIcon = "󰾅";
    }
    driver = powerProfiles.driver || "";
    const label = asString || (typeof prof === "number" ? prof.toString() : "Unknown");
    tooltipText = `Power profile: ${label}\nDriver: ${driver || "Unknown"}`;
  }

  Component.onCompleted: {
    const source = "import Quickshell.Services.UPower; PowerProfiles {}";
    const comp = Qt.createComponent(source);
    if (comp.status === Component.Ready) {
      powerProfiles = comp.createObject(root);
      available = !!powerProfiles;
      updateIcon();
    } else {
      comp.statusChanged.connect(function(status) {
        if (status === Component.Ready) {
          powerProfiles = comp.createObject(root);
          available = !!powerProfiles;
          updateIcon();
        }
      });
    }
  }

  Connections {
    target: powerProfiles
    function onProfileChanged() { updateIcon(); }
    function onDriverChanged() { updateIcon(); }
  }

  Label {
    id: label
    text: profileIcon
    ToolTip.visible: mouseArea.containsMouse && !!tooltipText
    ToolTip.text: tooltipText
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
  }
}
