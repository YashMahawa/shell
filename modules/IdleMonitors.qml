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
        // Rebuild the one-screen layout after the GPU/display link has resumed.
        // This also powers the chosen physical output before any fallback can
        // become visible.
        onResumed: Quickshell.execDetached([
            Quickshell.env("HOME") + "/.local/bin/caelestia-display",
            "auto"
        ])
        onLockRequested: root.lock.engage()
        onUnlockRequested: root.lock.release()
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
