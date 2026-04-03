pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    property bool locked: false
    property alias context: lockContext
    property var lockSurfaceItem: null

    readonly property Component sessionLockSurface: LockSurface {
        id: surface

        context: lockContext

        Component.onCompleted: root.lockSurfaceItem = surface
        Component.onDestruction: {
            if (root.lockSurfaceItem === surface)
                root.lockSurfaceItem = null;
        }
    }

    function focusLockSurface() {
        if (root.lockSurfaceItem && typeof root.lockSurfaceItem.clearPasswordField === "function")
            root.lockSurfaceItem.clearPasswordField();
    }

    function activateLock() {
        if (!root.locked) {
            lockContext.reset();
            root.locked = true;
        }

        Qt.callLater(function() {
            root.focusLockSurface();
        });
    }

    function deactivateLock() {
        lockContext.reset();
        root.locked = false;
    }

    LockContext {
        id: lockContext

        onUnlocked: {
            root.deactivateLock();
        }
    }

    WlSessionLock {
        id: lock

        locked: root.locked
        surface: root.sessionLockSurface
    }

    IpcHandler {
        target: "lockscreen"

        function lock() {
            root.activateLock();
        }

        function focus() {
            root.focusLockSurface();
        }

        function unlock() {
            root.deactivateLock();
        }
    }
}
