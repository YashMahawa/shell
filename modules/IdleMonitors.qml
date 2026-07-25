pragma ComponentBehavior: Bound

import "lock"
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.Internal
import qs.services

Scope {
    id: root

    required property Lock lock
    readonly property bool enabled: !GlobalConfig.general.idle.inhibitWhenAudio || !Players.list.some(p => p.isPlaying)

    function handleIdleAction(action: var): void {
        if (!action)
            return;

        if (action === "lock")
            lock.engage();
        else if (action === "unlock")
            lock.release();
        else if (typeof action === "string")
            Hypr.dispatch(Hypr.usingLua && ["dpms off", "dpms on"].includes(action) ? `hl.dsp.dpms({ action = "${action === "dpms off" ? "disable" : "enable"}" })` : action);
        else
            Quickshell.execDetached(action);
    }

    LogindManager {
        onAboutToSleep: {
            if (GlobalConfig.general.idle.lockBeforeSleep)
                root.lock.engage();
        }
        onLockRequested: root.lock.engage()
        onUnlockRequested: root.lock.release()
    }

    Variants {
        model: GlobalConfig.general.idle.timeouts

        IdleMonitor {
            required property var modelData

            enabled: root.enabled && (modelData.enabled ?? true)
            timeout: modelData.timeout
            respectInhibitors: modelData.respectInhibitors ?? true
            onIsIdleChanged: root.handleIdleAction(isIdle ? modelData.idleAction : modelData.returnAction)
        }
    }
}
