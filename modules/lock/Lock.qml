pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components.misc

Scope {
    property alias lock: lock

    WlSessionLock {
        id: lock

        signal unlock

        LockSurface {
            lock: lock
            pam: pam
        }
    }

    Pam {
        id: pam

        lock: lock
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "lock"
        description: "Lock the current session"
        onPressed: {
            if (!lock.locked)
                lock.locked = true;
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "unlock"
        description: "Unlock the current session"
        onPressed: lock.unlock()
    }

    IpcHandler {
        function safeLock(): bool {
            if (lock.locked)
                return true;
            lock.locked = true;
            return lock.locked;
        }

        function lock(): void {
            safeLock();
        }

        function unlock(): void {
            if (lock.locked)
                lock.unlock();
        }

        function isLocked(): bool {
            return lock.locked;
        }

        target: "lock"
    }
}
