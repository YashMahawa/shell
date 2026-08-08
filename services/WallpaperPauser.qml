pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower

Singleton {
    id: root

    // Battery state alone should not freeze an animated wallpaper. Pause only
    // while a real application window is focused on the current workspace.
    readonly property bool pauseOnBattery: false
    readonly property bool pauseWhenCovered: true
    property bool paused: false
    property string reason: ""
    property bool refreshPending: false

    function recalculate(): void {
        if (pauseOnBattery && UPower.onBattery) {
            paused = true;
            reason = "battery";
            return;
        }

        if (!pauseWhenCovered) {
            paused = false;
            reason = "";
            return;
        }

        // Quickshell's Hyprland workspace/toplevel model can lag behind a
        // workspace event. Ask Hyprland directly so an empty workspace cannot
        // inherit the previous workspace's focused window.
        if (activeWindowProc.running) {
            refreshPending = true;
            return;
        }
        activeWindowProc.running = true;
    }

    Connections {
        target: Hyprland

        function onFocusedWorkspaceChanged(): void {
            recalcTimer.restart();
        }

        function onFocusedMonitorChanged(): void {
            recalcTimer.restart();
        }

        function onRawEvent(event): void {
            const relevant = [
                "workspace", "workspacev2", "focusedmon", "activewindow",
                "openwindow", "closewindow", "movewindow", "fullscreen",
                "changefloatingmode", "minimize"
            ];
            if (relevant.includes(event.name))
                recalcTimer.restart();
        }
    }

    Connections {
        target: UPower

        function onOnBatteryChanged(): void {
            recalcTimer.restart();
        }
    }

    Timer {
        id: recalcTimer
        interval: 80
        onTriggered: root.recalculate()
    }

    Timer {
        running: true
        repeat: true
        // Hyprland events above provide the immediate updates. Retain a slow
        // safety reconciliation for missed compositor events without spawning
        // hyprctl every second while the desktop is idle.
        interval: 30000
        onTriggered: root.recalculate()
    }

    Component.onCompleted: recalcTimer.restart()

    Process {
        id: activeWindowProc

        command: ["hyprctl", "-j", "activewindow"]
        onExited: {
            if (root.refreshPending) {
                root.refreshPending = false;
                Qt.callLater(root.recalculate);
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const window = JSON.parse(text);
                    const covered = Boolean(window?.address
                        && (window?.mapped ?? true)
                        && !(window?.hidden ?? false));
                    root.paused = covered;
                    root.reason = covered ? "focused-window" : "";
                } catch (error) {
                    if (!text.trim())
                        return;
                    console.warn("Wallpaper pauser: invalid activewindow response:", error);
                }
            }
        }
    }

}
