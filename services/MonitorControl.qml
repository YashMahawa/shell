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

    function refresh(): void {
        if (!statusProc.running)
            statusProc.running = true;
    }

    function setControl(control: string, value): void {
        if (!root.available)
            return;
        if (control in root)
            root[control] = value;
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

    Component.onCompleted: refresh()

    Process {
        id: statusProc

        command: ["caelestia-monitor-control", "status"]
        onRunningChanged: root.busy = running

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
