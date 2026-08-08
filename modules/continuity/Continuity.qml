pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.services

// IPC bridge for clipboard — UI lives in the drawers popout system
// (bar/popouts/Clipboard.qml) so it matches other Caelestia panels.
Scope {
    id: root

    function openClipboard(): void {
        const focused = Hypr.focusedMonitor?.name ?? "";
        for (const screen of Screens.screens) {
            if (screen.name !== focused)
                continue;
            const bar = Visibilities.bars.get(screen);
            if (bar?.popouts)
                bar.popouts.detach("clipboard");
            return;
        }
        // Fallback: first available bar
        for (const screen of Screens.screens) {
            const bar = Visibilities.bars.get(screen);
            if (bar?.popouts) {
                bar.popouts.detach("clipboard");
                return;
            }
        }
    }

    function closeClipboard(): void {
        for (const screen of Screens.screens) {
            const bar = Visibilities.bars.get(screen);
            if (bar?.popouts?.detachedMode === "clipboard")
                bar.popouts.close();
        }
    }

    function openLink(page: string): void {
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
            target.linkPage = page;
            target.detach("link");
        }
    }

    IpcHandler {
        function open(): void { root.openClipboard(); }
        function openPhone(): void { root.openClipboard(); }
        function close(): void { root.closeClipboard(); }
        function toggle(): void {
            let open = false;
            for (const screen of Screens.screens) {
                const bar = Visibilities.bars.get(screen);
                if (bar?.popouts?.detachedMode === "clipboard") {
                    open = true;
                    break;
                }
            }
            if (open)
                root.closeClipboard();
            else
                root.openClipboard();
        }
        target: "clipboard"
    }

    IpcHandler {
        function open(): void { root.openLink("overview"); }
        function openDevices(): void { root.openLink("devices"); }
        function openCommands(): void { root.openLink("commands"); }
        function openFeatures(): void { root.openLink("features"); }
        function toggle(): void { root.openLink("overview"); }
        target: "continuity"
    }
}
