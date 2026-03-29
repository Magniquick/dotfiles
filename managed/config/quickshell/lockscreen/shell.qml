pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: root

    Component.onCompleted: console.log("[lockscreen/shell.qml] Root shell loaded");

    LockContext {
        id: lockContext

        onUnlocked: {
            lock.locked = false;
            Qt.quit();
        }
    }

    WlSessionLock {
        id: lock
        locked: true

        LockSurface {
            context: lockContext
        }
    }
}
