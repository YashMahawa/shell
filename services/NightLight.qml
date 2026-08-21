pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.services

Singleton {
    id: root

    property bool enabled: true
    property int temperature: 4500
    property string activeBackend: "none"
    property bool backendAvailable: activeBackend !== "none"
    property bool hdrActive: false
    property var priorState: ({})
    property int pendingTemperature: 4500
    property bool pendingEnabled: true
    property bool hyprsunsetAvailable: false
    property bool gammastepAvailable: false
    property bool wlsunsetAvailable: false
    property bool gsettingsAvailable: false

    readonly property real warmth: Math.max(0, Math.min(1, (6500 - temperature) / 4500))
    readonly property var supportedDdcPresets: ["5000", "6500", "7500", "9300", "user"]

    function detectBackend(): string {
        if (hyprsunsetAvailable)
            return "hyprsunset";
        if (gammastepAvailable)
            return "gammastep";
        if (wlsunsetAvailable)
            return "wlsunset";
        if (gsettingsAvailable)
            return "gsettings";
        if (MonitorControl.available)
            return "ddc";
        return "none";
    }

    function mapTemperatureToDdcPreset(temp: int): string {
        if (temp >= 6500)
            return "6500";
        if (temp >= 5750)
            return "6500";
        if (temp >= 4000)
            return "5000";
        return "user";
    }

    function checkHdrState(): void {
        let hdr = false;
        if (Hypr.monitors && Hypr.monitors.values) {
            for (const mon of Hypr.monitors.values) {
                if (mon.hdr || mon.hdrEnabled) {
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
        root.pendingEnabled = root.enabled;
        debounceTimer.restart();
    }

    function setEnabled(e: bool): void {
        root.pendingEnabled = e;
        if (!debounceTimer.running)
            root.pendingTemperature = root.temperature;
        debounceTimer.restart();
    }

    function applyPendingChanges(): void {
        const newEnabled = root.pendingEnabled;
        const newTemp = root.pendingTemperature;

        root.temperature = newTemp;
        root.enabled = newEnabled;

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
            case "ddc":
                applyDdc(newTemp);
                break;
            case "none":
            default:
                stopManagedProcess();
                break;
        }
    }

    function runManagedProcess(cmd: list<string>): void {
        if (proc.running)
            proc.running = false;
        proc.command = cmd;
        proc.running = true;
    }

    function stopManagedProcess(): void {
        if (proc.running)
            proc.running = false;
    }

    function savePriorState(): void {
        if (root.priorState && Object.keys(root.priorState).length > 0)
            return;
        if (root.activeBackend === "gsettings") {
            queryGsettingsPriorState();
        } else if (root.activeBackend === "ddc" && MonitorControl.available) {
            root.priorState = {
                temperature: MonitorControl.temperature ?? "6500"
            };
        }
    }

    function restorePriorState(): void {
        if (root.priorState && root.activeBackend === "gsettings") {
            const priorEn = root.priorState.gsettingsEnabled ?? false;
            const priorTemp = root.priorState.gsettingsTemp ?? 6500;
            applyGsettings(priorTemp, priorEn);
        } else if (root.priorState && root.activeBackend === "ddc" && MonitorControl.available) {
            const priorTemp = root.priorState.temperature ?? "6500";
            if (root.supportedDdcPresets.includes(priorTemp))
                MonitorControl.setControl("temperature", priorTemp);
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
        gsettingsQueryProc.command = ["gsettings", "get", "org.gnome.settings-daemon.plugins.color", "night-light-temperature"];
        gsettingsQueryProc.running = true;
    }

    function refreshCap(): void {
        checkProc.running = true;
    }

    function applyDdc(temp: int): void {
        if (!MonitorControl.available)
            return;
        const ddcPreset = mapTemperatureToDdcPreset(temp);
        if (root.supportedDdcPresets.includes(ddcPreset))
            MonitorControl.setControl("temperature", ddcPreset);
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

    Process {
        id: proc
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
                    const temp = parseInt(text.trim());
                    if (!isNaN(temp)) {
                        let st = root.priorState || ({});
                        st.gsettingsTemp = temp;
                        st.gsettingsEnabled = true;
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
            "command -v hyprsunset || true; echo '---'; command -v gammastep || true; echo '---'; command -v wlsunset || true; echo '---'; command -v gsettings || true"
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
