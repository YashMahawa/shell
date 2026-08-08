pragma Singleton

import Quickshell
import qs.components
import qs.services

Singleton {
    property var screens: new Map()
    property var bars: new Map()

    function closeAllHoverDrawers(): void {
        for (const visibilities of screens.values()) {
            visibilities.sidebar = false;
            visibilities.dashboard = false;
            visibilities.utilities = false;
            visibilities.osd = false;
        }
    }

    function load(screen: ShellScreen, visibilities: DrawerVisibilities): void {
        screens.set(Hypr.monitorFor(screen), visibilities);
    }

    function getForActive(): DrawerVisibilities {
        return screens.get(Hypr.focusedMonitor);
    }
}
