pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components.misc

Scope {
    id: root

    property alias lock: lock

    function writeLockState(state: string): void {
        lockStateProc.command = ["/home/yash/.local/bin/caelestia-lock-state", state];
        lockStateProc.running = true;
    }

    function engage(): bool {
        writeLockState("locked");
        lock.locked = true;
        return lock.locked;
    }

    function release(): void {
        writeLockState("unlocked");
        if (lock.locked)
            lock.unlock();
    }

    Process {
        id: lockStateProc
    }

    WlSessionLock {
        id: lock

        signal unlock
        onSecureChanged: {
            lockStateProc.command = [
                "/home/yash/.local/bin/caelestia-lock-state",
                secure ? "locked" : "unlocked"
            ];
            lockStateProc.running = true;
        }

        LockSurface {
            lock: lock
            pam: pam
        }
    }

    Pam {
        id: pam

        lock: lock
    }

    Loader {
        asynchronous: true
        active: false
        onLoaded: active = false

        // Force a load of a screencopy so the one in the lock works
        // My guess is the ICC backend loads async on first request, which if the lock is
        // the first request it fails to capture (because it's async and the compositor
        // refuses capture when locked)
        sourceComponent: ScreencopyView {
            captureSource: Quickshell.screens[0]
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "lock"
        description: "Lock the current session"
        onPressed: root.engage()
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "unlock"
        description: "Unlock the current session"
        onPressed: root.release()
    }

    IpcHandler {
        function safeLock(): bool {
            if (lock.locked)
                return true;
            return root.engage();
        }

        function lock(): void {
            safeLock();
        }

        function unlock(): void {
            root.release();
        }

        function isLocked(): bool {
            return lock.locked;
        }

        target: "lock"
    }
}
