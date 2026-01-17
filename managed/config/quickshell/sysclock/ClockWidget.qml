import QtQuick
import Quickshell
import Quickshell.Wayland
import "./common" as Common

PanelWindow {
    id: root
    WlrLayershell.layer: WlrLayer.Bottom
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 120

        Column {
            anchors.horizontalCenter: parent.horizontalCenter

            Text {
                id: day
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: Math.round(Common.Config.type.displayLarge.size * 2.8)
                color: Common.Config.textColor // default color for the rest of the text
                font.family: "Electroharmonix"
                style: Text.Raised
                styleColor: Common.Config.surface
                textFormat: Text.RichText
                renderType: Text.CurveRendering

                // For the first letter
                text: {
                    let fullDay = SysClock.format("dddd");
                    let firstLetter = fullDay.charAt(0);
                    let rest = fullDay.slice(1);
                    return "<span style='color:" + Common.Config.red.toString() + ";'>" + firstLetter + "</span>" + rest;
                }
            }
            Text {
                id: date
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: Math.round(Common.Config.type.headlineSmall.size * 1.25)
                color: Common.Config.textColor
                font.family: "The Last Shuriken"
                // text: Qt.formatDateTime(clock.date, "dd MMM yyyy")
                text: SysClock.format("dd MMM yyyy")
                style: Text.Raised
                styleColor: Common.Config.surface
            }
        }
    }
}
