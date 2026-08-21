pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.services

Singleton {
    id: root

    property bool enabled: false
    property int temperature: 4500
    property string activeBackend: "none"
    property bool backendAvailable: activeBackend !== "none"
    property bool hdrActive: false
    property var priorState: ({})
    property int pendingTemperature: 4500
    property bool pendingEnabled: false
    property bool loaded: false
    property bool hyprsunsetAvailable: false
    property bool gammastepAvailable: false
    property bool wlsunsetAvailable: false
    property bool gsettingsAvailable: false

    property var pendingCommand: []
    property var activeCommand: []
    property int processGeneration: 0

    readonly property real warmth: Math.max(0, Math.min(1, (6500 - temperature) / 4500))

    function detectBackend(): string {
        if (hyprsunsetAvailable)
            return "hyprsunset";
        if (gammastepAvailable)
            return "gammastep";
        if (wlsunsetAvailable)
            return "wlsunset";
        if (gsettingsAvailable)
            return "gsettings";
        return "none";
    }

    function checkHdrState(): void {
        let hdr = false;
        if (Hypr.monitors && Hypr.monitors.values) {
            for (const mon of Hypr.monitors.values) {
                if (mon.hdr || mon.hdrEnabled || mon.isHdr ||
                    mon.lastIpcObject?.hdr || mon.lastIpcObject?.hdrEnabled ||
                    mon.lastIpcObject?.hdr_enabled ||
                    (typeof mon.lastIpcObject?.bitsPerColor === "number" && mon.lastIpcObject.bitsPerColor > 8)) {
                    hdr = true;
                    break;
                }
            }
        }
        root.hdrActive = hdr;
    }

    function setWarmth(w: real): void {
        const clamped = Math.max(0, Math.min(1, w));
        const temp = Math.round(6500 - clamped * 4500);
        setTemperature(temp);
    }

    function setTemperature(temp: int): void {
        const clampedTemp = Math.max(2000, Math.min(6500, temp));
        root.pendingTemperature = clampedTemp;
        if (!debounceTimer.running)
            root.pendingEnabled = root.enabled;
        debounceTimer.restart();
    }

    function setEnabled(e: bool): void {
        root.pendingEnabled = e;
        if (!debounceTimer.running)
            root.pendingTemperature = root.temperature;
        debounceTimer.restart();
    }

    function saveState(): void {
        if (!stateFile)
            return;
        stateFile.setText(JSON.stringify({
            enabled: root.enabled,
            temperature: root.temperature
        }));
    }

    function applyPendingChanges(): void {
        const newEnabled = root.pendingEnabled;
        const newTemp = root.pendingTemperature;

        root.temperature = newTemp;
        root.enabled = newEnabled;

        saveState();
        checkHdrState();
        root.activeBackend = detectBackend();

        if (!root.enabled) {
            restorePriorState();
            stopManagedProcess();
            return;
        }

        savePriorState();

        if (root.hdrActive) {
            stopManagedProcess();
            return;
        }

        switch (root.activeBackend) {
            case "hyprsunset":
                runManagedProcess(["hyprsunset", "-t", String(newTemp)]);
                break;
            case "gammastep":
                runManagedProcess(["gammastep", "-P", "-O", String(newTemp)]);
                break;
            case "wlsunset":
                runManagedProcess(["wlsunset", "-T", String(newTemp)]);
                break;
            case "gsettings":
                applyGsettings(newTemp, true);
                break;
            case "none":
            default:
                stopManagedProcess();
                break;
        }
    }

    function runManagedProcess(cmd: list<string>): void {
        if (proc.running) {
            if (JSON.stringify(root.activeCommand) === JSON.stringify(cmd))
                return;
            root.pendingCommand = cmd;
            proc.running = false;
        } else {
            root.pendingCommand = [];
            root.activeCommand = cmd;
            proc.command = cmd;
            proc.running = true;
            root.processGeneration++;
        }
    }

    function stopManagedProcess(): void {
        root.pendingCommand = [];
        if (proc.running) {
            proc.running = false;
        }
    }

    function savePriorState(): void {
        if (root.priorState && Object.keys(root.priorState).length > 0)
            return;
        if (root.activeBackend === "gsettings") {
            queryGsettingsPriorState();
        }
    }

    function restorePriorState(): void {
        if (root.priorState && root.activeBackend === "gsettings") {
            const priorEn = root.priorState.gsettingsEnabled ?? false;
            const priorTemp = root.priorState.gsettingsTemp ?? 6500;
            applyGsettings(priorTemp, priorEn);
        }
        root.priorState = ({});
    }

    function applyGsettings(temp: int, en: bool): void {
        gsettingsProc.command = [
            "gsettings", "set", "org.gnome.settings-daemon.plugins.color", "night-light-temperature", String(temp)
        ];
        gsettingsProc.running = true;

        gsettingsEnProc.command = [
            "gsettings", "set", "org.gnome.settings-daemon.plugins.color", "night-light-enabled", en ? "true" : "false"
        ];
        gsettingsEnProc.running = true;
    }

    function queryGsettingsPriorState(): void {
        gsettingsQueryProc.command = [
            "sh", "-c",
            "gsettings get org.gnome.settings-daemon.plugins.color night-light-enabled; echo '---'; gsettings get org.gnome.settings-daemon.plugins.color night-light-temperature"
        ];
        gsettingsQueryProc.running = true;
    }

    function refreshCap(): void {
        checkProc.running = true;
    }

    Component.onCompleted: {
        refreshCap();
        checkHdrState();
    }

    Connections {
        function onValuesChanged(): void {
            root.checkHdrState();
            if (root.enabled)
                root.applyPendingChanges();
        }

        target: Hypr.monitors
    }

    Timer {
        id: debounceTimer

        interval: 150
        onTriggered: root.applyPendingChanges()
    }

    FileView {
        id: stateFile

        path: `${Paths.state}/night-light.json`
        printErrors: false
        onLoaded: {
            try {
                const state = JSON.parse(text());
                if (state && typeof state === "object") {
                    if (typeof state.enabled === "boolean") {
                        root.enabled = state.enabled;
                        root.pendingEnabled = state.enabled;
                    }
                    if (typeof state.temperature === "number") {
                        root.temperature = state.temperature;
                        root.pendingTemperature = state.temperature;
                    }
                }
            } catch (e) {}
            root.loaded = true;
            if (root.enabled && root.activeBackend !== "none")
                root.applyPendingChanges();
        }
        onLoadFailed: error => {
            root.loaded = true;
            root.enabled = false;
            root.pendingEnabled = false;
        }
    }

    Process {
        id: proc

        onRunningChanged: {
            if (!running) {
                root.activeCommand = [];
                if (root.pendingCommand && root.pendingCommand.length > 0) {
                    const cmd = root.pendingCommand;
                    root.pendingCommand = [];
                    if (root.enabled && !root.hdrActive && root.activeBackend !== "none") {
                        root.activeCommand = cmd;
                        proc.command = cmd;
                        proc.running = true;
                        root.processGeneration++;
                    }
                }
            }
        }
    }

    Process {
        id: gsettingsProc
    }

    Process {
        id: gsettingsEnProc
    }

    Process {
        id: gsettingsQueryProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parts = text.split("---");
                    if (parts.length >= 2) {
                        const enStr = parts[0].trim().toLowerCase();
                        const tempVal = parseInt(parts[1].trim());
                        let st = root.priorState || ({});
                        st.gsettingsEnabled = (enStr === "true");
                        if (!isNaN(tempVal))
                            st.gsettingsTemp = tempVal;
                        root.priorState = st;
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: checkProc

        command: [
            "sh", "-c",
            "command -v hyprsunset || true; echo '---'; command -v gammastep || true; echo '---'; command -v wlsunset || true; echo '---'; gsettings get org.gnome.settings-daemon.plugins.color night-light-temperature >/dev/null 2>&1 && command -v gsettings || true"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("---");
                if (parts.length >= 4) {
                    root.hyprsunsetAvailable = parts[0].trim().length > 0;
                    root.gammastepAvailable = parts[1].trim().length > 0;
                    root.wlsunsetAvailable = parts[2].trim().length > 0;
                    root.gsettingsAvailable = parts[3].trim().length > 0;
                    root.activeBackend = root.detectBackend();
                    if (root.enabled && root.activeBackend !== "none")
                        root.applyPendingChanges();
                }
            }
        }
    }
}

