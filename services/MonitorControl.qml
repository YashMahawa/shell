pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool available: false
    property bool busy: false
    property string connector: ""
    property string model: ""
    property int brightness: 0
    property int contrast: 50
    property int redGain: 50
    property int greenGain: 50
    property int blueGain: 50
    property int volume: 0
    property bool muted: false
    property string temperature: "6500"
    property string input: "hdmi1"
    property string errorMessage: ""
    property var queuedWrite: null
    property double lastRefreshAt: 0
    property bool refreshPending: false
    property string outputSignature: ""

    function currentOutputSignature(): string {
        const outputs = [];
        for (const monitor of Hypr.monitors.values) {
            if (!monitor.name.startsWith("eDP-")
                    && !monitor.name.startsWith("LVDS-")
                    && !monitor.name.startsWith("DSI-")) {
                outputs.push(`${monitor.name}:${monitor.description ?? ""}`);
            }
        }
        return outputs.sort().join("|");
    }

    function refresh(force = false): void {
        if (statusProc.running) {
            root.refreshPending = root.refreshPending || force;
            return;
        }

        // Opening the display page remains effectively immediate, while duplicate
        // construction/IPC events cannot launch several expensive DDC reads.
        const now = Date.now();
        if (!force && now - root.lastRefreshAt < 5000)
            return;
        root.lastRefreshAt = now;
        statusProc.running = true;
    }

    function setControl(control: string, value): void {
        if (!root.available)
            return;
        root.queuedWrite = ({ control, value });
        writeDebounce.restart();
    }

    function startQueuedWrite(): void {
        if (!root.queuedWrite || writeProc.running)
            return;
        const request = root.queuedWrite;
        root.queuedWrite = null;
        writeProc.command = [
            "caelestia-monitor-control", "set",
            request.control, String(request.value)
        ];
        writeProc.running = true;
    }

    Component.onCompleted: {
        outputSignature = currentOutputSignature();
        refresh(true);
    }

    Connections {
        function onValuesChanged(): void {
            const nextSignature = root.currentOutputSignature();
            if (nextSignature === root.outputSignature)
                return;
            root.outputSignature = nextSignature;
            hotplugRefresh.restart();
        }

        target: Hypr.monitors
    }

    Timer {
        id: hotplugRefresh

        interval: 900
        onTriggered: root.refresh(true)
    }

    // HDMI HPD commonly stays asserted while the monitor changes HDR/input or
    // briefly loses mains power, so Hyprland emits no useful connector change.
    // A cheap single-VCP probe makes controls recover without repeatedly
    // reading every supported monitor property.
    Timer {
        interval: 5000
        repeat: true
        running: root.outputSignature !== ""
        triggeredOnStart: false
        onTriggered: {
            if (!healthProc.running)
                healthProc.running = true;
        }
    }

    Process {
        id: healthProc
        command: ["caelestia-monitor-control", "brightness"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const state = JSON.parse(text);
                    const recovered = !root.available;
                    root.available = state.available ?? false;
                    root.connector = state.connector ?? root.connector;
                    root.model = state.model ?? root.model;
                    root.brightness = state.brightness ?? root.brightness;
                    root.errorMessage = "";
                    if (recovered)
                        root.refresh(true);
                } catch (error) {
                    root.available = false;
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim()) {
                    root.available = false;
                    root.errorMessage = qsTr("Monitor controls will retry automatically");
                }
            }
        }
    }

    Process {
        id: statusProc

        command: ["caelestia-monitor-control", "status"]
        onRunningChanged: root.busy = running
        onExited: {
            if (root.refreshPending) {
                root.refreshPending = false;
                Qt.callLater(() => root.refresh(true));
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const state = JSON.parse(text);
                    root.available = state.available ?? false;
                    root.connector = state.connector ?? "";
                    root.model = state.model ?? "";
                    root.brightness = state.brightness ?? root.brightness;
                    root.contrast = state.contrast ?? root.contrast;
                    root.redGain = state.redGain ?? root.redGain;
                    root.greenGain = state.greenGain ?? root.greenGain;
                    root.blueGain = state.blueGain ?? root.blueGain;
                    root.volume = state.volume ?? root.volume;
                    root.muted = state.muted ?? root.muted;
                    root.temperature = state.temperature ?? root.temperature;
                    root.input = state.input ?? root.input;
                    root.errorMessage = "";
                } catch (error) {
                    root.available = false;
                    root.errorMessage = qsTr("Monitor controls are unavailable");
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim()) {
                    root.available = false;
                    root.errorMessage = text.trim();
                }
            }
        }
    }

    Timer {
        id: writeDebounce

        interval: 180
        onTriggered: root.startQueuedWrite()
    }

    Process {
        id: writeProc

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim()) {
                    try {
                        const result = JSON.parse(text);
                        if (result.control in root)
                            root[result.control] = result.value;
                        root.available = true;
                        root.errorMessage = "";
                    } catch (error) {
                        root.errorMessage = qsTr("Monitor did not confirm the change");
                    }
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    root.errorMessage = text.trim();
            }
        }
        onExited: {
            if (root.queuedWrite)
                writeDebounce.restart();
        }
    }
}
