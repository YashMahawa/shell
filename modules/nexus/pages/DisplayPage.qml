pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Display")

    property var monitor: Hypr.focusedMonitor ?? (Hypr.monitors.values[0] ?? null)
    property string selectedResolution: monitor ? `${monitor.width}x${monitor.height}` : "preferred"
    property real selectedRefresh: Math.round((monitor?.refreshRate ?? 60) * 100) / 100
    property real selectedScale: monitor?.scale ?? 1
    property int selectedTransform: monitor?.transform ?? 0
    property var modes: []
    property string pendingToken: ""
    property int revertSeconds: 0
    property string statusMessage: ""
    property bool statusIsError: false

    readonly property var brightnessMonitor: Brightness.getMonitor("active")
    readonly property bool external: monitor && !monitor.name.startsWith("eDP-")
        && !monitor.name.startsWith("LVDS-") && !monitor.name.startsWith("DSI-")
    readonly property list<MenuItem> scaleItems: [
        MenuItem { text: "100%" },
        MenuItem { text: "125%" },
        MenuItem { text: "150%" },
        MenuItem { text: "175%" },
        MenuItem { text: "200%" }
    ]
    readonly property list<MenuItem> orientationItems: [
        MenuItem { text: qsTr("Landscape") },
        MenuItem { text: qsTr("Portrait left") },
        MenuItem { text: qsTr("Landscape flipped") },
        MenuItem { text: qsTr("Portrait right") }
    ]
    readonly property list<MenuItem> temperatureItems: [
        MenuItem { text: "6500 K" },
        MenuItem { text: "7500 K" },
        MenuItem { text: "9300 K" },
        MenuItem { text: qsTr("Custom") }
    ]
    readonly property list<MenuItem> inputItems: [
        MenuItem { text: "HDMI 1" },
        MenuItem { text: "HDMI 2" },
        MenuItem { text: "DisplayPort" }
    ]

    function parsedMode(raw: string): var {
        const match = raw.match(/^(\d+x\d+)@([\d.]+)Hz$/);
        return match ? ({ resolution: match[1], refresh: Number(match[2]) }) : null;
    }

    function resolutions(): var {
        const result = [];
        for (const raw of modes) {
            const mode = parsedMode(raw);
            if (mode && !result.includes(mode.resolution))
                result.push(mode.resolution);
        }
        return result.length ? result : [selectedResolution];
    }

    function refreshRates(): var {
        const result = [];
        for (const raw of modes) {
            const mode = parsedMode(raw);
            if (mode && mode.resolution === selectedResolution && !result.includes(mode.refresh))
                result.push(mode.refresh);
        }
        return (result.length ? result : [selectedRefresh]).sort((a, b) => b - a);
    }

    function scaleIndex(value: real): int {
        const values = [1, 1.25, 1.5, 1.75, 2];
        let best = 0;
        for (let i = 1; i < values.length; i++) {
            if (Math.abs(values[i] - value) < Math.abs(values[best] - value))
                best = i;
        }
        return best;
    }

    function applyDisplay(): void {
        if (!monitor)
            return;
        monitorProc.exec([
            "caelestia-display", "apply",
            "--name", monitor.name,
            "--resolution", `${selectedResolution}@${selectedRefresh}`,
            "--position", "0x0",
            "--scale", String(selectedScale),
            "--transform", String(selectedTransform)
        ]);
    }

    Component.onCompleted: MonitorControl.refresh()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Process {
            id: modeProc

            running: true
            command: ["hyprctl", "monitors", "-j"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const displays = JSON.parse(text);
                        const live = displays.find(item => item.focused) ?? displays[0];
                        if (!live)
                            return;
                        root.monitor = live;
                        root.modes = live.availableModes ?? [];
                        root.selectedResolution = `${live.width}x${live.height}`;
                        root.selectedRefresh = Math.round((live.refreshRate ?? 60) * 100) / 100;
                        root.selectedScale = live.scale ?? 1;
                        root.selectedTransform = live.transform ?? 0;
                    } catch (error) {
                        root.statusMessage = qsTr("Could not read display modes");
                        root.statusIsError = true;
                    }
                }
            }
        }

        Process {
            id: monitorProc

            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const result = JSON.parse(text);
                        root.pendingToken = result.token ?? "";
                        root.revertSeconds = result.timeout ?? 20;
                        root.statusMessage = qsTr("Keep this display setting within %1 seconds").arg(root.revertSeconds);
                        root.statusIsError = false;
                        revertTimer.restart();
                    } catch (error) {
                        if (text.trim())
                            root.statusMessage = text.trim();
                    }
                }
            }
            stderr: StdioCollector {
                onStreamFinished: {
                    if (text.trim()) {
                        root.statusMessage = text.trim();
                        root.statusIsError = true;
                    }
                }
            }
            onExited: {
                Hyprland.refreshMonitors();
                modeProc.running = true;
            }
        }

        Process {
            id: confirmProc

            stdout: StdioCollector {
                onStreamFinished: {
                    if (text.trim())
                        root.statusMessage = text.trim();
                }
            }
        }

        Timer {
            id: revertTimer

            interval: 1000
            repeat: true
            onTriggered: {
                root.revertSeconds--;
                if (root.revertSeconds <= 0) {
                    stop();
                    root.pendingToken = "";
                    root.statusMessage = qsTr("Previous display setting restored");
                    Hyprland.refreshMonitors();
                    modeProc.running = true;
                } else {
                    root.statusMessage = qsTr("Keep this display setting within %1 seconds").arg(root.revertSeconds);
                }
            }
        }

        Component {
            id: dynamicMenuItem
            MenuItem {}
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: overviewLayout.implicitHeight + overviewLayout.anchors.margins * 2

            RowLayout {
                id: overviewLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.large

                StyledRect {
                    implicitWidth: 64
                    implicitHeight: 64
                    radius: Tokens.rounding.large
                    color: Colours.palette.m3primaryContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: root.external ? "desktop_windows" : "laptop"
                        fontStyle: Tokens.font.icon.large
                        color: Colours.palette.m3primary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    StyledText {
                        text: MonitorControl.available
                            ? MonitorControl.model
                            : (root.monitor?.description ?? qsTr("Built-in display"))
                        font: Tokens.font.title.small
                    }
                    StyledText {
                        text: root.monitor
                            ? `${root.monitor.width}×${root.monitor.height} · ${Math.round(root.monitor.refreshRate ?? 60)} Hz`
                            : qsTr("No active display")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                    StyledText {
                        text: root.external
                            ? qsTr("External-only · laptop panel disabled automatically")
                            : qsTr("Laptop-only · an external monitor will take over automatically")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3primary
                    }
                }

                MaterialIcon {
                    text: "sync"
                    fontStyle: Tokens.font.icon.medium
                    color: Colours.palette.m3primary
                }
            }
        }

        SectionHeader { text: qsTr("Display quality") }

        SliderRow {
            Layout.fillWidth: true
            first: true
            icon: "brightness_6"
            label: qsTr("Brightness")
            valueLabel: `${Math.round(value * 100)}%`
            value: root.brightnessMonitor?.brightness ?? 0
            enabled: root.brightnessMonitor !== null
            onMoved: value => root.brightnessMonitor?.setBrightness(value)
        }

        SliderRow {
            Layout.fillWidth: true
            visible: MonitorControl.available
            icon: "contrast"
            label: qsTr("Contrast")
            valueLabel: `${Math.round(value * 100)}%`
            value: MonitorControl.contrast / 100
            onMoved: value => MonitorControl.setControl("contrast", Math.round(value * 100))
        }

        SelectRow {
            Layout.fillWidth: true
            visible: MonitorControl.available
            last: true
            label: qsTr("White point")
            subtext: qsTr("6500 K is recommended for accurate desktop colour")
            menuItems: root.temperatureItems
            active: ["6500", "7500", "9300", "user"].indexOf(MonitorControl.temperature)
            fallbackText: MonitorControl.temperature === "user" ? qsTr("Custom") : `${MonitorControl.temperature} K`
            fallbackIcon: "thermostat"
            onSelected: item => {
                const values = ["6500", "7500", "9300", "user"];
                MonitorControl.setControl("temperature", values[root.temperatureItems.indexOf(item)] ?? "6500");
            }
        }

        SectionHeader {
            visible: MonitorControl.available
            text: qsTr("Colour calibration")
        }

        SliderRow {
            Layout.fillWidth: true
            visible: MonitorControl.available
            first: true
            icon: "format_color_fill"
            label: qsTr("Red gain")
            valueLabel: `${Math.round(value * 100)}`
            value: MonitorControl.redGain / 100
            onMoved: value => MonitorControl.setControl("redGain", Math.round(value * 100))
        }

        SliderRow {
            Layout.fillWidth: true
            visible: MonitorControl.available
            icon: "format_color_fill"
            label: qsTr("Green gain")
            valueLabel: `${Math.round(value * 100)}`
            value: MonitorControl.greenGain / 100
            onMoved: value => MonitorControl.setControl("greenGain", Math.round(value * 100))
        }

        SliderRow {
            Layout.fillWidth: true
            visible: MonitorControl.available
            last: true
            icon: "format_color_fill"
            label: qsTr("Blue gain")
            valueLabel: `${Math.round(value * 100)}`
            value: MonitorControl.blueGain / 100
            onMoved: value => MonitorControl.setControl("blueGain", Math.round(value * 100))
        }

        SectionHeader { text: qsTr("Resolution and layout") }

        SelectRow {
            Layout.fillWidth: true
            first: true
            label: qsTr("Resolution")
            subtext: qsTr("Native resolution gives the sharpest image")
            menuItems: root.resolutions().map(value => dynamicMenuItem.createObject(root, { text: value }))
            active: Math.max(0, root.resolutions().indexOf(root.selectedResolution))
            fallbackText: root.selectedResolution
            fallbackIcon: "aspect_ratio"
            onSelected: item => {
                root.selectedResolution = item.text;
                root.selectedRefresh = root.refreshRates()[0] ?? root.selectedRefresh;
            }
        }

        SelectRow {
            Layout.fillWidth: true
            label: qsTr("Refresh rate")
            subtext: qsTr("Rates supported by the current connection")
            menuItems: root.refreshRates().map(value => dynamicMenuItem.createObject(root, { text: `${value} Hz` }))
            active: Math.max(0, root.refreshRates().findIndex(value => Math.abs(value - root.selectedRefresh) < 0.02))
            fallbackText: `${root.selectedRefresh} Hz`
            fallbackIcon: "speed"
            onSelected: item => root.selectedRefresh = Number(item.text.replace(" Hz", ""))
        }

        SelectRow {
            Layout.fillWidth: true
            label: qsTr("Scale")
            subtext: qsTr("Text and interface size")
            menuItems: root.scaleItems
            active: root.scaleIndex(root.selectedScale)
            fallbackText: `${Math.round(root.selectedScale * 100)}%`
            fallbackIcon: "zoom_in"
            onSelected: item => {
                const values = [1, 1.25, 1.5, 1.75, 2];
                root.selectedScale = values[root.scaleItems.indexOf(item)] ?? 1;
            }
        }

        SelectRow {
            Layout.fillWidth: true
            last: true
            label: qsTr("Orientation")
            subtext: qsTr("Rotate the active display")
            menuItems: root.orientationItems
            active: Math.max(0, Math.min(root.selectedTransform, 3))
            fallbackText: root.orientationItems[Math.max(0, Math.min(root.selectedTransform, 3))].text
            fallbackIcon: "screen_rotation"
            onSelected: item => root.selectedTransform = root.orientationItems.indexOf(item)
        }

        SectionHeader {
            visible: MonitorControl.available
            text: qsTr("Monitor hardware")
        }

        SelectRow {
            Layout.fillWidth: true
            visible: MonitorControl.available
            first: true
            label: qsTr("Input")
            subtext: qsTr("Switch the monitor's physical input")
            menuItems: root.inputItems
            active: ["hdmi1", "hdmi2", "displayport"].indexOf(MonitorControl.input)
            fallbackText: ({ hdmi1: "HDMI 1", hdmi2: "HDMI 2", displayport: "DisplayPort" })[MonitorControl.input] ?? MonitorControl.input
            fallbackIcon: "input"
            onSelected: item => {
                const values = ["hdmi1", "hdmi2", "displayport"];
                MonitorControl.setControl("input", values[root.inputItems.indexOf(item)] ?? "hdmi1");
            }
        }

        SliderRow {
            Layout.fillWidth: true
            visible: MonitorControl.available
            icon: MonitorControl.muted ? "volume_off" : "volume_up"
            label: qsTr("Built-in speaker volume")
            valueLabel: MonitorControl.muted ? qsTr("Muted") : `${Math.round(value * 100)}%`
            value: MonitorControl.volume / 100
            onMoved: value => MonitorControl.setControl("volume", Math.round(value * 100))
        }

        ToggleRow {
            Layout.fillWidth: true
            visible: MonitorControl.available
            last: true
            text: qsTr("Mute monitor speakers")
            subtext: qsTr("Controls the monitor amplifier, independent of PipeWire")
            checked: MonitorControl.muted
            onToggled: MonitorControl.setControl("muted", checked)
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: actionLayout.implicitHeight + actionLayout.anchors.margins * 2

            RowLayout {
                id: actionLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.fillWidth: true
                    text: root.statusMessage || qsTr("Layout changes revert automatically unless kept")
                    color: root.statusIsError ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.Wrap
                }

                TextButton {
                    visible: root.pendingToken === ""
                    text: qsTr("Apply safely")
                    onClicked: root.applyDisplay()
                }

                TextButton {
                    visible: root.pendingToken !== ""
                    text: qsTr("Keep")
                    onClicked: {
                        confirmProc.exec(["caelestia-display", "confirm", root.pendingToken]);
                        root.pendingToken = "";
                        revertTimer.stop();
                    }
                }
            }
        }
    }
}
