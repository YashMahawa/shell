pragma Singleton

import Quickshell
import Caelestia.Config

Singleton {
    id: root

    function isInternalName(name: string): bool {
        return ["eDP-", "LVDS-", "DSI-"].some(prefix => name.startsWith(prefix));
    }

    readonly property list<ShellScreen> physicalScreens: Quickshell.screens.filter(
        s => !s.name.startsWith("HEADLESS-")
    )
    readonly property ShellScreen preferredScreen:
        physicalScreens.find(s => !isInternalName(s.name))
        ?? physicalScreens.find(s => isInternalName(s.name))
        ?? null
    readonly property list<ShellScreen> screens:
        preferredScreen && GlobalConfig.forScreen(preferredScreen.name).enabled
        ? [preferredScreen] : []

    function isExcluded(screen: ShellScreen): bool {
        return screen !== preferredScreen || !GlobalConfig.forScreen(screen.name).enabled;
    }
}
