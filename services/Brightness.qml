pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components.misc

Singleton {
    id: root

    property list<var> ddcMonitors: []
    readonly property var ddcMonitorMap: {
        const map = {};
        for (const m of ddcMonitors)
            map[m.connector] = m;
        return map;
    }
    readonly property list<Monitor> monitors: variants.instances // qmllint disable incompatible-type
    property bool appleDisplayPresent: false
    property real pendingPointerDelta: 0

    function getMonitorForScreen(screen: ShellScreen): var {
        return monitors.find(m => m.modelData === screen); // qmllint disable missing-property
    }

    function getMonitor(query: string): var {
        if (query === "active") {
            return monitors.find(m => Hypr.monitorFor(m.modelData)?.focused); // qmllint disable missing-property
        }

        if (query.startsWith("model:")) {
            const model = query.slice(6);
            return monitors.find(m => m.modelData.model === model); // qmllint disable missing-property
        }

        if (query.startsWith("serial:")) {
            const serial = query.slice(7);
            return monitors.find(m => m.modelData.serialNumber === serial); // qmllint disable missing-property
        }

        if (query.startsWith("id:")) {
            const id = parseInt(query.slice(3), 10);
            return monitors.find(m => Hypr.monitorFor(m.modelData)?.id === id); // qmllint disable missing-property
        }

        return monitors.find(m => m.modelData.name === query); // qmllint disable missing-property
    }

    function adjustBrightnessAtPointer(delta: real): void {
        pendingPointerDelta += delta;
        if (!cursorProc.running)
            cursorProc.running = true;
    }

    function increaseBrightness(): void {
        adjustBrightnessAtPointer(GlobalConfig.services.brightnessIncrement);
    }

    function decreaseBrightness(): void {
        adjustBrightnessAtPointer(-GlobalConfig.services.brightnessIncrement);
    }

    onMonitorsChanged: {
        ddcMonitors = [];
        ddcProc.running = true;
    }

    Variants {
        id: variants

        // The shell intentionally exposes one physical screen. Using raw
        // Quickshell.screens here also creates transient eDP/HEADLESS monitor
        // objects during hotplug, leaving the OSD bound to a null screen.
        model: Screens.screens

        Monitor {}
    }

    Process {
        running: true
        command: ["sh", "-c", "asdbctl get"] // To avoid warnings if asdbctl is not installed
        stdout: StdioCollector {
            onStreamFinished: root.appleDisplayPresent = text.trim().length > 0
        }
    }

    Process {
        id: ddcProc

        // Access can be granted by udev ACLs without membership in the i2c
        // group. Let ddcutil test the device directly instead of rejecting a
        // valid per-user ACL such as /dev/i2c-3 on the connected Acer.
        running: true
        command: ["ddcutil", "detect", "--brief"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const monitor = JSON.parse(text);
                    root.ddcMonitors = [{
                        busNum: monitor.bus,
                        connector: monitor.connector
                    }];
                } catch (error) {
                    root.ddcMonitors = [];
                }
            }
        }
    }

    Process {
        id: cursorProc

        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const delta = root.pendingPointerDelta;
                root.pendingPointerDelta = 0;
                try {
                    const position = JSON.parse(text);
                    const hyprMonitor = Hypr.monitors.values.find(candidate => {
                        const scale = Math.max(candidate.scale ?? 1, 0.25);
                        const width = (candidate.width ?? 0) / scale;
                        const height = (candidate.height ?? 0) / scale;
                        return position.x >= candidate.x && position.x < candidate.x + width
                            && position.y >= candidate.y && position.y < candidate.y + height;
                    });
                    const monitor = root.getMonitor(hyprMonitor?.name ?? "")
                        ?? root.getMonitor("active");
                    if (monitor)
                        monitor.setBrightness(monitor.brightness + delta);
                } catch (error) {
                    const monitor = root.getMonitor("active");
                    if (monitor)
                        monitor.setBrightness(monitor.brightness + delta);
                }
            }
        }
        onExited: {
            if (root.pendingPointerDelta !== 0)
                Qt.callLater(() => cursorProc.running = true);
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "brightnessUp"
        description: "Increase brightness"
        onPressed: root.increaseBrightness()
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "brightnessDown"
        description: "Decrease brightness"
        onPressed: root.decreaseBrightness()
    }

    IpcHandler {
        function get(): real {
            return getFor("active");
        }

        // Allows searching by active/model/serial/id/name
        function getFor(query: string): real {
            return root.getMonitor(query)?.brightness ?? -1;
        }

        function set(value: string): string {
            return setFor("active", value);
        }

        // Handles brightness value like brightnessctl: 0.1, +0.1, 0.1-, 10%, +10%, 10%-
        function setFor(query: string, value: string): string {
            const monitor = root.getMonitor(query);
            if (!monitor)
                return "Invalid monitor: " + query;

            let targetBrightness;
            if (value.endsWith("%-")) {
                const percent = parseFloat(value.slice(0, -2));
                targetBrightness = monitor.brightness - (percent / 100);
            } else if (value.startsWith("+") && value.endsWith("%")) {
                const percent = parseFloat(value.slice(1, -1));
                targetBrightness = monitor.brightness + (percent / 100);
            } else if (value.endsWith("%")) {
                const percent = parseFloat(value.slice(0, -1));
                targetBrightness = percent / 100;
            } else if (value.startsWith("+")) {
                const increment = parseFloat(value.slice(1));
                targetBrightness = monitor.brightness + increment;
            } else if (value.endsWith("-")) {
                const decrement = parseFloat(value.slice(0, -1));
                targetBrightness = monitor.brightness - decrement;
            } else if (value.includes("%") || value.includes("-") || value.includes("+")) {
                return `Invalid brightness format: ${value}\nExpected: 0.1, +0.1, 0.1-, 10%, +10%, 10%-`;
            } else {
                targetBrightness = parseFloat(value);
            }

            if (isNaN(targetBrightness))
                return `Failed to parse value: ${value}\nExpected: 0.1, +0.1, 0.1-, 10%, +10%, 10%-`;

            monitor.setBrightness(targetBrightness);

            return `Set monitor ${monitor.modelData.name} brightness to ${+monitor.brightness.toFixed(2)}`;
        }

        target: "brightness"
    }

    component Monitor: QtObject {
        id: monitor

        required property var modelData
        readonly property bool valid: modelData !== null && modelData !== undefined
        readonly property string name: valid ? modelData.name : ""
        readonly property string model: valid ? modelData.model : ""
        readonly property var ddcInfo: valid ? (root.ddcMonitorMap[name] ?? null) : null
        readonly property bool isDdc: ddcInfo !== null
        readonly property string busNum: ddcInfo?.busNum ?? ""
        readonly property bool isAppleDisplay: valid && root.appleDisplayPresent && model.startsWith("StudioDisplay")
        readonly property bool isInternalPanel: valid && (name.startsWith("eDP-")
            || name.startsWith("LVDS-") || name.startsWith("DSI-"))
        property int maxBrightness: isAppleDisplay ? 101 : 100
        property real brightness: 1.0
        property real queuedBrightness: NaN
        property bool initPending: false

        readonly property Process initProc: Process {
            stdout: StdioCollector {
                onStreamFinished: {
                    if (monitor.isAppleDisplay) {
                        const val = parseInt(text.trim());
                        if (Number.isFinite(val))
                            monitor.brightness = val / monitor.maxBrightness;
                    } else {
                        const parts = text.trim().split(/\s+/);
                        const cur = parseInt(parts[3]);
                        const max = parseInt(parts[4]);
                        if (Number.isFinite(cur) && Number.isFinite(max) && max > 0) {
                            monitor.maxBrightness = max;
                            monitor.brightness = cur / max;
                        }
                    }
                }
            }
            onExited: {
                if (!Number.isFinite(monitor.brightness)) {
                    monitor.brightness = 1.0;
                }
                if (monitor.initPending) {
                    monitor.initPending = false;
                    Qt.callLater(() => monitor.initBrightness());
                }
            }
        }

        readonly property Timer timer: Timer {
            interval: 500
            onTriggered: {
                if (!isNaN(monitor.queuedBrightness)) {
                    monitor.setBrightness(monitor.queuedBrightness);
                    monitor.queuedBrightness = NaN;
                }
            }
        }

        function setBrightness(value: real): void {
            if (!valid)
                return;
            value = Math.max(0, Math.min(1, value));
            const rounded = Math.round(value * 100);
            const targetRaw = Math.round(value * maxBrightness);
            const currentRaw = Math.round(brightness * (isInternalPanel ? 100 : maxBrightness));
            if (isInternalPanel ? Math.round(brightness * 100) === rounded : currentRaw === targetRaw)
                return;

            // Never fall back to brightnessctl for an external monitor while
            // DDC discovery is still pending; that would dim the laptop panel.
            if (!isAppleDisplay && !isDdc && !isInternalPanel)
                return;

            if (isDdc && timer.running) {
                queuedBrightness = value;
                return;
            }

            brightness = value;

            if (isAppleDisplay)
                Quickshell.execDetached(["asdbctl", "set", targetRaw]);
            else if (isDdc)
                Quickshell.execDetached(["ddcutil", "-b", busNum, "setvcp", "10", targetRaw]);
            else if (isInternalPanel)
                Quickshell.execDetached(["brightnessctl", "s", `${rounded}%`]);

            if (isDdc)
                timer.restart();
        }

        function initBrightness(): void {
            if (!valid)
                return;
            if (isAppleDisplay)
                initProc.command = ["asdbctl", "get"];
            else if (isDdc)
                initProc.command = ["ddcutil", "-b", busNum, "getvcp", "10", "--brief"];
            else if (isInternalPanel)
                initProc.command = ["sh", "-c", "echo a b c $(brightnessctl g) $(brightnessctl m)"];
            else {
                brightness = 0;
                return;
            }

            initProc.running = true;
        }

        onBusNumChanged: initBrightness()
        Component.onCompleted: initBrightness()
    }
}
