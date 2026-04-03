pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

ShellRoot {
    Component.onCompleted: Quickshell.watchFiles = false

    LockController {
        id: controller
        locked: true
    }

    Connections {
        target: controller.context

        function onUnlocked() {
            Qt.quit();
        }
    }
}
