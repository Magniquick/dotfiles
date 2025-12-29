import QtQuick
import Quickshell
import Quickshell.Wayland

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
                font.pixelSize: 160
                color: "#cdd6f4"  // default color for the rest of the text
                font.family: "Electroharmonix"
                style: Text.Raised
                styleColor: "#1e1e2b"
                textFormat: Text.RichText
                renderType: Text.CurveRendering

                // For the first letter
                text: {
                    let fullDay = SysClock.format("dddd");
                    let firstLetter = fullDay.charAt(0);
                    let rest = fullDay.slice(1);
                    return "<span style='color:#f38ba8;'>" + firstLetter + "</span>" + rest;
                }
            }
            Text {
                id: date
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: 30
                color: "#cdd6f4"
                // font.family: "Electroharmonix"
                font.family: "The Last Shuriken"
                // text: Qt.formatDateTime(clock.date, "dd MMM yyyy")
                text: SysClock.format("dd MMM yyyy")
                style: Text.Raised
                styleColor: "#1e1e2b"
            }
        }
    }
}
