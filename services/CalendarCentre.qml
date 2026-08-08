pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    function open(page): void {
        page = page || "calendar";
        Visibilities.closeAllHoverDrawers();
        const focused = Hypr.focusedMonitor?.name ?? "";
        let target = null;
        for (const screen of Screens.screens) {
            const popouts = Visibilities.bars.get(screen)?.popouts;
            if (!popouts)
                continue;
            popouts.close();
            if (screen.name === focused)
                target = popouts;
            else if (!target)
                target = popouts;
        }
        if (target) {
            target.calendarPage = page;
            target.detach("calendar");
        }
    }

    function close(): void {
        for (const screen of Screens.screens) {
            const popouts = Visibilities.bars.get(screen)?.popouts;
            if (popouts?.detachedMode === "calendar")
                popouts.close();
        }
    }

    function status(): string {
        const values = [];
        for (const screen of Screens.screens) {
            const popouts = Visibilities.bars.get(screen)?.popouts;
            values.push(`${screen.name}:${popouts?.detachedMode ?? "missing"}`);
        }
        return values.join(",");
    }

    IpcHandler {
        function open(): void { root.open("calendar"); }
        function openTimetable(): void { root.open("timetable"); }
        function openSettings(): void { root.open("settings"); }
        function close(): void { root.close(); }
        function status(): string { return root.status(); }
        target: "calendarcentre"
    }
}
