import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

// Codex owns the realtime renderer (waveform, caption and call controls).
// Caelestia owns its Wayland compositor lifecycle and placement.
Scope {
    id: root

    property var configuredAddresses: ({})

    function configureVoiceSurfaces(): void {
        for (const toplevel of Hypr.toplevels.values) {
            if (toplevel?.title !== "Codex Voice")
                continue;

            const address = String(toplevel.address ?? "");
            if (!address || configuredAddresses[address])
                continue;

            configuredAddresses[address] = true;
            const selector = `address:0x${address}`;
            const workspaceName = String(toplevel.lastIpcObject.workspace?.name ?? "");
            if (workspaceName === "special:codex-voice") {
                const targetWorkspace = Hypr.focusedMonitor?.activeWorkspace?.id ?? 1;
                Hypr.dispatch(Hypr.usingLua
                    ? `hl.dsp.window.move({ window = "${selector}", workspace = "${targetWorkspace}", follow = false })`
                    : `movetoworkspacesilent ${targetWorkspace},${selector}`);
            }
            if (!toplevel.lastIpcObject.floating)
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.window.toggle_floating({ window = "${selector}" })` : `setfloating ${selector}`);
            if (!toplevel.lastIpcObject.pinned)
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.window.pin({ window = "${selector}" })` : `pin ${selector}`);
        }
    }

    Timer {
        id: settleTimer
        interval: 90
        repeat: false
        onTriggered: root.configureVoiceSurfaces()
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (["openwindow", "windowtitle", "windowtitlev2", "movewindow"].includes(event.name))
                settleTimer.restart();
            else if (event.name === "closewindow")
                root.configuredAddresses = ({});
        }
    }

    Component.onCompleted: settleTimer.start()
}
