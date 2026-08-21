pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.services
import qs.utils

Singleton {
    id: root

    property var registeredOverlays: ({})
    property var savedState: ({})
    property bool isReady: false

    function saveState() {
        const payload = {
            version: 1,
            overlays: root.registeredOverlays
        };
        stateFile.setText(JSON.stringify(payload, null, 2));
    }

    function formatAddress(addr) {
        if (!addr)
            return "";
        return addr.startsWith("0x") ? addr : ("0x" + addr);
    }

    function computeStableId(toplevel) {
        if (!toplevel)
            return "";
        const ipc = toplevel.lastIpcObject || {};
        const cls = ipc.class || ipc.initialClass || "";
        const title = ipc.initialTitle || ipc.title || toplevel.title || "";
        const pid = ipc.pid ? String(ipc.pid) : "";

        if (cls && title) {
            return `${cls}:${title}`;
        } else if (cls) {
            return pid ? `${cls}:${pid}` : cls;
        } else if (title) {
            return title;
        }
        return formatAddress(toplevel.address || ipc.address);
    }

    function findToplevel(windowId) {
        if (!windowId || windowId === "" || windowId === "active") {
            return Hypr.activeToplevel;
        }

        const raw = String(windowId).trim();
        const norm = raw.toLowerCase().replace(/^0x/, "");
        const toplevels = Hypr.toplevels ? Hypr.toplevels.values : [];

        // 1. Exact address match
        for (let i = 0; i < toplevels.length; i++) {
            const t = toplevels[i];
            if (!t)
                continue;

            const addr = String(t.address || "").toLowerCase().replace(/^0x/, "");
            const ipcAddr = String(t.lastIpcObject?.address || "").toLowerCase().replace(/^0x/, "");
            if (addr === norm || ipcAddr === norm) {
                return t;
            }
        }

        // 2. Class or initialClass match
        for (let i = 0; i < toplevels.length; i++) {
            const t = toplevels[i];
            if (!t)
                continue;

            const ipc = t.lastIpcObject || {};
            const cls = String(ipc.class || "").toLowerCase();
            const initialCls = String(ipc.initialClass || "").toLowerCase();
            if (cls === norm || initialCls === norm) {
                return t;
            }
        }

        // 3. Title or initialTitle match
        for (let i = 0; i < toplevels.length; i++) {
            const t = toplevels[i];
            if (!t)
                continue;

            const ipc = t.lastIpcObject || {};
            const title = String(ipc.title || t.title || "").toLowerCase();
            const initialTitle = String(ipc.initialTitle || "").toLowerCase();
            if (title === norm || initialTitle === norm) {
                return t;
            }
        }

        // 4. Composite stableId match
        for (let i = 0; i < toplevels.length; i++) {
            const t = toplevels[i];
            if (!t)
                continue;

            const stableId = computeStableId(t).toLowerCase();
            if (stableId === norm || stableId.replace(/^0x/, "") === norm) {
                return t;
            }
        }

        return null;
    }

    function getMonitorForToplevel(toplevel) {
        if (!toplevel)
            return Hypr.focusedMonitor;

        const ipcMon = toplevel.lastIpcObject?.monitor;
        const monitors = Hypr.monitors ? Hypr.monitors.values : [];

        for (let i = 0; i < monitors.length; i++) {
            const m = monitors[i];
            if (!m)
                continue;
            if (m.name === ipcMon || m.id === ipcMon || String(m.id) === String(ipcMon) || m.lastIpcObject?.name === ipcMon) {
                return m;
            }
        }

        return Hypr.focusedMonitor;
    }

    function dispatchCmd(standardCmd, luaCmd) {
        if (Hypr.usingLua && luaCmd) {
            Hypr.dispatch(luaCmd);
        } else {
            Hypr.dispatch(standardCmd);
        }
    }

    function registerOverlay(windowId, anchorPos, pinState, clickthroughState) {
        const toplevel = findToplevel(windowId);
        if (!toplevel) {
            return JSON.stringify({
                success: false,
                error: "Invalid window identifier: " + windowId
            });
        }

        const rawAddr = toplevel.address || toplevel.lastIpcObject?.address;
        if (!rawAddr) {
            return JSON.stringify({
                success: false,
                error: "Window missing address"
            });
        }
        const fullAddr = formatAddress(rawAddr);
        const normAddr = fullAddr.toLowerCase();

        const ipc = toplevel.lastIpcObject || {};
        const stableId = computeStableId(toplevel);

        let info = root.registeredOverlays[normAddr];

        if (!info) {
            for (const key in root.registeredOverlays) {
                if (root.registeredOverlays[key].stableId === stableId) {
                    info = root.registeredOverlays[key];
                    break;
                }
            }
        }

        if (!info) {
            info = {
                stableId: stableId,
                address: fullAddr,
                class: ipc.class || "",
                title: ipc.title || "",
                initialClass: ipc.initialClass || "",
                initialTitle: ipc.initialTitle || "",
                pid: ipc.pid || 0,
                originalFloating: ipc.floating ?? false,
                originalPinned: ipc.pinned ?? false,
                originalWorkspace: ipc.workspace?.name || String(ipc.workspace?.id ?? "") || toplevel.workspace?.name || "",
                originalMonitor: ipc.monitor || "",
                originalAt: [ipc.at?.[0] ?? 0, ipc.at?.[1] ?? 0],
                originalSize: [ipc.size?.[0] ?? 800, ipc.size?.[1] ?? 600],
                anchored: null,
                pinned: ipc.pinned ?? false,
                clickthrough: false
            };
        }

        info.address = fullAddr;

        if (!(ipc.floating ?? false)) {
            dispatchCmd(`setfloating address:${fullAddr}`, `hl.dsp.window.float({ action = "enable", window = "address:${fullAddr}" })`);
        }

        let currentOverlay = Object.assign({}, info);

        if (anchorPos && anchorPos !== "" && anchorPos !== "none") {
            applyAnchor(toplevel, anchorPos);
            currentOverlay.anchored = anchorPos;
        }

        if (pinState === "true" || pinState === "1" || pinState === "enable") {
            if (!ipc.pinned) {
                dispatchCmd(`pin address:${fullAddr}`, `hl.dsp.window.pin({ window = "address:${fullAddr}" })`);
            }
            currentOverlay.pinned = true;
        }

        if (clickthroughState === "true" || clickthroughState === "1" || clickthroughState === "enable") {
            dispatchCmd(`setprop address:${fullAddr} noinput 1`, `hl.dsp.setprop({ window = "address:${fullAddr}", prop = "noinput", value = "1" })`);
            dispatchCmd(`setprop address:${fullAddr} passthrough 1`, `hl.dsp.setprop({ window = "address:${fullAddr}", prop = "passthrough", value = "1" })`);
            currentOverlay.clickthrough = true;
        }

        const newMap = Object.assign({}, root.registeredOverlays);
        newMap[normAddr] = currentOverlay;
        root.registeredOverlays = newMap;
        root.saveState();

        return JSON.stringify({
            success: true,
            action: "registered",
            overlay: currentOverlay
        });
    }

    function unregisterOverlay(windowId) {
        const toplevel = findToplevel(windowId);
        if (!toplevel) {
            return JSON.stringify({
                success: false,
                error: "Invalid window identifier: " + windowId
            });
        }

        const rawAddr = toplevel.address || toplevel.lastIpcObject?.address;
        if (!rawAddr) {
            return JSON.stringify({
                success: false,
                error: "Window missing address"
            });
        }
        const fullAddr = formatAddress(rawAddr);
        const normAddr = fullAddr.toLowerCase();

        const info = root.registeredOverlays[normAddr];
        const ipc = toplevel.lastIpcObject || {};

        if (info) {
            if (info.clickthrough) {
                dispatchCmd(`setprop address:${fullAddr} noinput 0`, `hl.dsp.setprop({ window = "address:${fullAddr}", prop = "noinput", value = "0" })`);
                dispatchCmd(`setprop address:${fullAddr} passthrough 0`, `hl.dsp.setprop({ window = "address:${fullAddr}", prop = "passthrough", value = "0" })`);
            }

            if (!info.originalPinned && ipc.pinned) {
                dispatchCmd(`pin address:${fullAddr}`, `hl.dsp.window.pin({ window = "address:${fullAddr}" })`);
            }

            const currentWs = ipc.workspace?.name || String(ipc.workspace?.id ?? "");
            if (info.originalWorkspace && currentWs && info.originalWorkspace !== currentWs) {
                dispatchCmd(`movetoworkspacesilent ${info.originalWorkspace},address:${fullAddr}`,
                            `hl.dsp.window.move({ workspace = "${info.originalWorkspace}", silent = true, window = "address:${fullAddr}" })`);
            }

            if (!info.originalFloating) {
                dispatchCmd(`settiled address:${fullAddr}`, `hl.dsp.window.float({ action = "disable", window = "address:${fullAddr}" })`);
            } else {
                if (info.originalAt && info.originalAt.length === 2) {
                    dispatchCmd(`movewindowpixel exact ${info.originalAt[0]} ${info.originalAt[1]},address:${fullAddr}`,
                                `hl.dsp.window.move({ x = ${info.originalAt[0]}, y = ${info.originalAt[1]}, window = "address:${fullAddr}" })`);
                }
                if (info.originalSize && info.originalSize.length === 2) {
                    dispatchCmd(`resizewindowpixel exact ${info.originalSize[0]} ${info.originalSize[1]},address:${fullAddr}`,
                                `hl.dsp.window.resize({ x = ${info.originalSize[0]}, y = ${info.originalSize[1]}, exact = true, window = "address:${fullAddr}" })`);
                }
            }

            const newMap = Object.assign({}, root.registeredOverlays);
            delete newMap[normAddr];
            root.registeredOverlays = newMap;
            root.saveState();

            return JSON.stringify({
                success: true,
                action: "unregistered",
                address: fullAddr
            });
        } else {
            if (ipc.floating) {
                dispatchCmd(`settiled address:${fullAddr}`, `hl.dsp.window.float({ action = "disable", window = "address:${fullAddr}" })`);
            }
            return JSON.stringify({
                success: true,
                action: "unregistered",
                address: fullAddr,
                note: "was not in registry"
            });
        }
    }

    function applyAnchor(toplevel, position, marginStr) {
        if (!toplevel)
            return false;

        const rawAddr = toplevel.address || toplevel.lastIpcObject?.address;
        if (!rawAddr)
            return false;
        const fullAddr = formatAddress(rawAddr);

        const monitor = getMonitorForToplevel(toplevel);
        const monX = monitor?.x ?? monitor?.lastIpcObject?.x ?? 0;
        const monY = monitor?.y ?? monitor?.lastIpcObject?.y ?? 0;
        const monW = monitor?.width ?? monitor?.lastIpcObject?.width ?? 1920;
        const monH = monitor?.height ?? monitor?.lastIpcObject?.height ?? 1080;

        const ipc = toplevel.lastIpcObject || {};
        const winW = ipc.size?.[0] ?? 800;
        const winH = ipc.size?.[1] ?? 600;

        const margin = (marginStr !== undefined && marginStr !== null && marginStr !== "") ? parseInt(marginStr, 10) : 10;
        const pos = String(position || "center").toLowerCase();

        let targetX = monX + Math.round((monW - winW) / 2);
        let targetY = monY + Math.round((monH - winH) / 2);

        switch (pos) {
            case "top-left":
            case "topleft":
                targetX = monX + margin;
                targetY = monY + margin;
                break;
            case "top-right":
            case "topright":
                targetX = monX + monW - winW - margin;
                targetY = monY + margin;
                break;
            case "bottom-left":
            case "bottomleft":
                targetX = monX + margin;
                targetY = monY + monH - winH - margin;
                break;
            case "bottom-right":
            case "bottomright":
                targetX = monX + monW - winW - margin;
                targetY = monY + monH - winH - margin;
                break;
            case "top":
                targetX = monX + Math.round((monW - winW) / 2);
                targetY = monY + margin;
                break;
            case "bottom":
                targetX = monX + Math.round((monW - winW) / 2);
                targetY = monY + monH - winH - margin;
                break;
            case "left":
                targetX = monX + margin;
                targetY = monY + Math.round((monH - winH) / 2);
                break;
            case "right":
                targetX = monX + monW - winW - margin;
                targetY = monY + Math.round((monH - winH) / 2);
                break;
            case "center":
            case "middle":
                targetX = monX + Math.round((monW - winW) / 2);
                targetY = monY + Math.round((monH - winH) / 2);
                break;
            default:
                break;
        }

        dispatchCmd(`movewindowpixel exact ${targetX} ${targetY},address:${fullAddr}`,
                    `hl.dsp.window.move({ x = ${targetX}, y = ${targetY}, window = "address:${fullAddr}" })`);

        const normAddr = fullAddr.toLowerCase();
        if (root.registeredOverlays[normAddr]) {
            const newMap = Object.assign({}, root.registeredOverlays);
            newMap[normAddr].anchored = pos;
            root.registeredOverlays = newMap;
            root.saveState();
        }

        return true;
    }

    function pinOverlay(windowId, enableStr) {
        const toplevel = findToplevel(windowId);
        if (!toplevel) {
            return JSON.stringify({
                success: false,
                error: "Invalid window identifier: " + windowId
            });
        }
        const rawAddr = toplevel.address || toplevel.lastIpcObject?.address;
        const fullAddr = formatAddress(rawAddr);
        const normAddr = fullAddr.toLowerCase();

        if (!root.registeredOverlays[normAddr]) {
            registerOverlay(windowId);
        }

        const ipc = toplevel.lastIpcObject || {};
        let shouldEnable = !ipc.pinned;
        if (enableStr === "true" || enableStr === "1" || enableStr === "enable") {
            shouldEnable = true;
        } else if (enableStr === "false" || enableStr === "0" || enableStr === "disable") {
            shouldEnable = false;
        }

        if (shouldEnable !== ipc.pinned) {
            dispatchCmd(`pin address:${fullAddr}`, `hl.dsp.window.pin({ window = "address:${fullAddr}" })`);
        }

        if (root.registeredOverlays[normAddr]) {
            const newMap = Object.assign({}, root.registeredOverlays);
            newMap[normAddr].pinned = shouldEnable;
            root.registeredOverlays = newMap;
            root.saveState();
        }

        return JSON.stringify({
            success: true,
            pinned: shouldEnable,
            address: fullAddr
        });
    }

    function clickthroughOverlay(windowId, enableStr) {
        const toplevel = findToplevel(windowId);
        if (!toplevel) {
            return JSON.stringify({
                success: false,
                error: "Invalid window identifier: " + windowId
            });
        }
        const rawAddr = toplevel.address || toplevel.lastIpcObject?.address;
        const fullAddr = formatAddress(rawAddr);
        const normAddr = fullAddr.toLowerCase();

        if (!root.registeredOverlays[normAddr]) {
            registerOverlay(windowId);
        }

        const currentOverlay = root.registeredOverlays[normAddr] || {};
        let shouldEnable = !currentOverlay.clickthrough;
        if (enableStr === "true" || enableStr === "1" || enableStr === "enable") {
            shouldEnable = true;
        } else if (enableStr === "false" || enableStr === "0" || enableStr === "disable") {
            shouldEnable = false;
        }

        const val = shouldEnable ? 1 : 0;
        dispatchCmd(`setprop address:${fullAddr} noinput ${val}`, `hl.dsp.setprop({ window = "address:${fullAddr}", prop = "noinput", value = "${val}" })`);
        dispatchCmd(`setprop address:${fullAddr} passthrough ${val}`, `hl.dsp.setprop({ window = "address:${fullAddr}", prop = "passthrough", value = "${val}" })`);

        if (root.registeredOverlays[normAddr]) {
            const newMap = Object.assign({}, root.registeredOverlays);
            newMap[normAddr].clickthrough = shouldEnable;
            root.registeredOverlays = newMap;
            root.saveState();
        }

        return JSON.stringify({
            success: true,
            clickthrough: shouldEnable,
            address: fullAddr
        });
    }

    function listOverlays() {
        root.reconcileOverlays();
        return JSON.stringify(Object.values(root.registeredOverlays));
    }

    function toggleOverlay(windowId) {
        const toplevel = findToplevel(windowId);
        if (!toplevel) {
            return JSON.stringify({
                success: false,
                error: "Invalid window identifier: " + windowId
            });
        }
        const rawAddr = toplevel.address || toplevel.lastIpcObject?.address;
        const fullAddr = formatAddress(rawAddr);
        const normAddr = fullAddr.toLowerCase();

        if (root.registeredOverlays[normAddr]) {
            return unregisterOverlay(windowId);
        } else {
            return registerOverlay(windowId);
        }
    }

    function reconcileOverlays() {
        const activeToplevels = Hypr.toplevels ? Hypr.toplevels.values : [];
        const sourceMap = (Object.keys(root.registeredOverlays).length > 0) ? root.registeredOverlays : root.savedState;
        const newRegistered = {};

        for (const key in sourceMap) {
            const entry = sourceMap[key];
            if (!entry)
                continue;

            let matchedToplevel = null;

            // 1. Try matching active window by address
            if (entry.address) {
                const normEntryAddr = formatAddress(entry.address).toLowerCase();
                for (let i = 0; i < activeToplevels.length; i++) {
                    const t = activeToplevels[i];
                    if (!t)
                        continue;
                    const addr = formatAddress(t.address || t.lastIpcObject?.address).toLowerCase();
                    if (addr === normEntryAddr) {
                        matchedToplevel = t;
                        break;
                    }
                }
            }

            // 2. Try matching active window by stable identity (class, title, initialTitle, pid)
            if (!matchedToplevel && entry.class) {
                for (let i = 0; i < activeToplevels.length; i++) {
                    const t = activeToplevels[i];
                    if (!t)
                        continue;

                    const ipc = t.lastIpcObject || {};
                    const cls = ipc.class || ipc.initialClass || "";
                    const title = ipc.initialTitle || ipc.title || t.title || "";
                    const pid = ipc.pid || 0;

                    if (cls === entry.class && (title === entry.title || title === entry.initialTitle || (entry.pid && pid === entry.pid))) {
                        matchedToplevel = t;
                        break;
                    }
                }
            }

            if (matchedToplevel) {
                const rawAddr = matchedToplevel.address || matchedToplevel.lastIpcObject?.address;
                const fullAddr = formatAddress(rawAddr);
                const normAddr = fullAddr.toLowerCase();
                const ipc = matchedToplevel.lastIpcObject || {};

                const updatedEntry = Object.assign({}, entry, {
                    address: fullAddr,
                    stableId: computeStableId(matchedToplevel)
                });

                if (!(ipc.floating ?? false)) {
                    dispatchCmd(`setfloating address:${fullAddr}`, `hl.dsp.window.float({ action = "enable", window = "address:${fullAddr}" })`);
                }

                if (updatedEntry.pinned && !ipc.pinned) {
                    dispatchCmd(`pin address:${fullAddr}`, `hl.dsp.window.pin({ window = "address:${fullAddr}" })`);
                }

                if (updatedEntry.clickthrough) {
                    dispatchCmd(`setprop address:${fullAddr} noinput 1`, `hl.dsp.setprop({ window = "address:${fullAddr}", prop = "noinput", value = "1" })`);
                    dispatchCmd(`setprop address:${fullAddr} passthrough 1`, `hl.dsp.setprop({ window = "address:${fullAddr}", prop = "passthrough", value = "1" })`);
                }

                if (updatedEntry.anchored) {
                    applyAnchor(matchedToplevel, updatedEntry.anchored);
                }

                newRegistered[normAddr] = updatedEntry;
            }
        }

        root.registeredOverlays = newRegistered;
        root.saveState();
    }

    FileView {
        id: stateFile

        path: `${Paths.state}/overlay-manager-state.json`
        printErrors: false

        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (parsed && typeof parsed === "object") {
                    root.savedState = parsed.overlays || parsed || {};
                    root.reconcileOverlays();
                }
            } catch (e) {
                console.warn("OverlayManager: Unable to parse state file:", e);
            }
            root.isReady = true;
        }

        onLoadFailed: error => {
            root.isReady = true;
            if (error === FileViewError.FileNotFound) {
                Qt.callLater(() => root.saveState());
            }
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            const n = event.name;
            if (n === "closewindow" || n === "openwindow" || n === "movewindow" || n === "configreloaded") {
                reconcileTimer.restart();
            }
        }
    }

    Timer {
        id: reconcileTimer

        interval: 50
        repeat: false
        onTriggered: root.reconcileOverlays()
    }

    Component.onDestruction: {
        root.saveState();
    }

    IpcHandler {
        target: "overlay"

        function register(windowId: string, anchorPos: string, pinState: string, clickthroughState: string): string {
            return root.registerOverlay(windowId, anchorPos, pinState, clickthroughState);
        }

        function float(windowId: string, anchorPos: string, pinState: string, clickthroughState: string): string {
            return root.registerOverlay(windowId, anchorPos, pinState, clickthroughState);
        }

        function unregister(windowId: string): string {
            return root.unregisterOverlay(windowId);
        }

        function unoverlay(windowId: string): string {
            return root.unregisterOverlay(windowId);
        }

        function anchor(position: string, windowId: string, margin: string): string {
            const toplevel = root.findToplevel(windowId);
            if (!toplevel) {
                return JSON.stringify({
                    success: false,
                    error: "Invalid window identifier: " + windowId
                });
            }
            const rawAddr = toplevel.address || toplevel.lastIpcObject?.address;
            const fullAddr = root.formatAddress(rawAddr);
            const normAddr = fullAddr.toLowerCase();
            if (!root.registeredOverlays[normAddr]) {
                root.registerOverlay(windowId);
            }
            const ok = root.applyAnchor(toplevel, position, margin);
            return JSON.stringify({
                success: ok,
                position: position,
                address: fullAddr
            });
        }

        function pin(windowId: string, enableStr: string): string {
            return root.pinOverlay(windowId, enableStr);
        }

        function clickthrough(windowId: string, enableStr: string): string {
            return root.clickthroughOverlay(windowId, enableStr);
        }

        function list(): string {
            return root.listOverlays();
        }

        function toggle(windowId: string): string {
            return root.toggleOverlay(windowId);
        }

        function restore(windowId: string): string {
            return root.unregisterOverlay(windowId);
        }

        function restoreAll(): string {
            const addresses = Object.keys(root.registeredOverlays);
            let restoredCount = 0;
            for (let i = 0; i < addresses.length; i++) {
                const addr = addresses[i];
                root.unregisterOverlay(addr);
                restoredCount++;
            }
            return JSON.stringify({
                success: true,
                restored: restoredCount
            });
        }
    }
}
