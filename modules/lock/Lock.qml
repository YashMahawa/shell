pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components.misc

Scope {
    property alias lock: lock

    WlSessionLock {
        id: lock

        signal unlock

        // Preserve lock intent across a shell crash. Do not clear a recovery
        // marker merely because a newly started lock is initially unlocked.
        onLockedChanged: {
            if (locked)
                lockStateProc.running = true;
        }

        LockSurface {
            lock: lock
            pam: pam
        }
    }

    Process {
        id: lockStateProc
        command: [Quickshell.env("HOME") + "/.local/bin/caelestia-lock-state", "locked"]
    }

    Pam {
        id: pam

        lock: lock
    }

    Loader {
        asynchronous: true
        active: true
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
        onPressed: lock.locked = true
    }

    IpcHandler {
        function safeLock(): bool {
            lock.locked = true;
            return true;
        }

        function lock(): void {
            lock.locked = true;
        }

        function isLocked(): bool {
            return lock.secure;
        }

        target: "lock"
    }
}
