pragma Singleton

import Quickshell
import Caelestia.Config

Singleton {
    id: root

    // HEADLESS outputs are a compositor safety net for physical hotplug. They
    // intentionally have no shell UI, while still preventing Qt from entering
    // its fragile zero-output placeholder path.
    readonly property list<ShellScreen> screens: Quickshell.screens.filter(
        s => !s.name.startsWith("HEADLESS-") && GlobalConfig.forScreen(s.name).enabled
    )

    function isExcluded(screen: ShellScreen): bool {
        return !GlobalConfig.forScreen(screen.name).enabled;
    }
}
