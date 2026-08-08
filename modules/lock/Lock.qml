pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components.misc

Scope {
    id: root

    property alias lock: lock
    property bool engagePending: false

    function writeLockState(state: string): void {
        lockStateProc.command = ["/home/yash/.local/bin/caelestia-lock-state", state];
        lockStateProc.running = true;
    }

    function engage(): bool {
        if (lock.locked || engagePending)
            return true;
        engagePending = true;
        captureProc.running = true;
        return true;
    }

    function release(): void {
        engagePending = false;
        if (captureProc.running)
            captureProc.running = false;
        writeLockState("unlocked");
        if (lock.locked)
            lock.unlock();
    }

    Process {
        id: lockStateProc
    }

    Process {
        id: captureProc

        command: ["/home/yash/.local/bin/caelestia-lock-capture"]
        onExited: {
            if (!root.engagePending)
                return;
            root.engagePending = false;
            root.writeLockState("locked");
            lock.locked = true;
        }
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
        id: screencopyPreloader

        asynchronous: true
        // Prime Quickshell's screencopy/ICC backend while the session is still
        // unlocked. If its first initialization happens after the session-lock
        // protocol is active, Hyprland correctly refuses the capture and the
        // lock surface has nothing available for its blur effect.
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
