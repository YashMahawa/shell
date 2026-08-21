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
    readonly property bool audioPlaying: Players.list.some(p => p.isPlaying)

    function timeoutEnabled(modelData: var): bool {
        if (!GlobalConfig.general.idle.inhibitWhenAudio || !audioPlaying)
            return true;
        // Audio should prevent lock/suspend, but music playback should not keep
        // an external monitor's backlight on forever. Video apps can still use
        // the standard Wayland idle inhibitor respected by this monitor.
        return modelData.idleAction === "dpms off";
    }

    function handleIdleAction(action: var): void {
        if (!action)
            return;

        if (action === "lock")
            lock.lock.locked = true;
        else if (typeof action === "string")
            Hypr.dispatch(Hypr.usingLua && ["dpms off", "dpms on"].includes(action) ? `hl.dsp.dpms({ action = "${action === "dpms off" ? "disable" : "enable"}" })` : action);
        else
            Quickshell.execDetached(action);
    }

    LogindManager {
        // The system pre-sleep service is the single lock owner. PrepareForSleep
        // is only a notification and arrives too late to safely race another
        // lock request from the root sleep transaction.
        // Output recovery is handled by the persistent display watcher after
        // Hyprland reports a real connector change. Do not reconfigure outputs
        // from the sleep transition itself; the GPU may still be resuming.
        onLockRequested: root.lock.lock.locked = true
    }

    Variants {
        model: GlobalConfig.general.idle.timeouts

        IdleMonitor {
            required property var modelData

            enabled: root.timeoutEnabled(modelData) && (modelData.enabled ?? true)
            timeout: modelData.timeout
            respectInhibitors: modelData.respectInhibitors ?? true
            onIsIdleChanged: root.handleIdleAction(isIdle ? modelData.idleAction : modelData.returnAction)
        }
    }
}
