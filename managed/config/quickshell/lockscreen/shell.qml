pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: root

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
