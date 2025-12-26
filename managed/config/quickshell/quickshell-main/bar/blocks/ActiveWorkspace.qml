import "../"
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell.Io

BarText {
    // text: {
    //   var str = activeWindowTitle
    //   return str.length > chopLength ? str.slice(0, chopLength) + '...' : str;
    // }

    property int chopLength
    property string activeWindowTitle

    function hyprEvent(e) {
        titleProc.running = true;
    }

    Component.onCompleted: {
        Hyprland.rawEvent.connect(hyprEvent);
    }

    Process {
        id: titleProc

        command: ["sh", "-c", "hyprctl activewindow | grep title: | sed 's/^[^:]*: //'"]
        running: true

        stdout: SplitParser {
            onRead: data => {
                return activeWindowTitle = data;
            }
        }
    }
}
