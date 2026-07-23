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

    property var selectedMonitor: Hypr.focusedMonitor ?? (Hypr.monitors.values[0] ?? null)
    property string selectedResolution: selectedMonitor ? `${selectedMonitor.width}x${selectedMonitor.height}` : "preferred"
    property real selectedRefresh: Math.round((selectedMonitor?.refreshRate ?? 60) * 100) / 100
    property real selectedScale: selectedMonitor?.scale ?? 1
    property int selectedX: selectedMonitor?.x ?? 0
    property int selectedY: selectedMonitor?.y ?? 0
    property int selectedTransform: selectedMonitor?.transform ?? 0
    property bool selectedEnabled: true
    property bool mirrorFocused: false
    property string statusMessage: ""
    property bool statusIsError: false
    property var modesByMonitor: ({})
    property var liveMonitorsByName: ({})
    property bool saveAfterApply: false
    property bool pointerFollowsMonitor: true
    property bool warpPointerWithWorkspace: false

    readonly property list<MenuItem> scaleItems: [
        MenuItem {
            text: "100%"
        },
        MenuItem {
            text: "125%"
        },
        MenuItem {
            text: "150%"
        },
        MenuItem {
            text: "175%"
        },
        MenuItem {
            text: "200%"
        }
    ]
    readonly property list<MenuItem> orientationItems: [
        MenuItem {
            text: qsTr("Landscape")
        },
        MenuItem {
            text: qsTr("Portrait left")
        },
        MenuItem {
            text: qsTr("Landscape flipped")
        },
        MenuItem {
            text: qsTr("Portrait right")
        }
    ]

    function currentResolutionLabel(): string {
        const m = liveMonitorsByName[selectedMonitor?.name] ?? selectedMonitor;
        if (!m)
            return qsTr("Current");
        return `${m.width}x${m.height}`;
    }

    function scaleIndex(scale: real): int {
        const values = [1, 1.25, 1.5, 1.75, 2];
        let best = 0;
        let bestDelta = Math.abs(values[0] - scale);
        for (let i = 1; i < values.length; i++) {
            const delta = Math.abs(values[i] - scale);
            if (delta < bestDelta) {
                best = i;
                bestDelta = delta;
            }
        }
        return best;
    }

    function parsedMode(raw: string): var {
        const match = raw.match(/^(\d+x\d+)@([\d.]+)Hz$/);
        return match ? ({ resolution: match[1], refresh: Number(match[2]) }) : null;
    }

    function monitorModes(): var {
        return modesByMonitor[selectedMonitor?.name] ?? [];
    }

    function supportedResolutions(): var {
        const values = [qsTr("Preferred")];
        for (const raw of monitorModes()) {
            const mode = parsedMode(raw);
            if (mode && !values.includes(mode.resolution))
                values.push(mode.resolution);
        }
        if (values.length === 1)
            values.push(currentResolutionLabel());
        return values;
    }

    function supportedRefreshRates(): var {
        const resolution = selectedResolution === qsTr("Preferred") || selectedResolution === "preferred" ? currentResolutionLabel() : selectedResolution;
        const values = [];
        for (const raw of monitorModes()) {
            const mode = parsedMode(raw);
            if (mode && mode.resolution === resolution && !values.includes(mode.refresh))
                values.push(mode.refresh);
        }
        if (!values.length)
            values.push(Math.round(((liveMonitorsByName[selectedMonitor?.name]?.refreshRate) ?? selectedMonitor?.refreshRate ?? 60) * 100) / 100);
        return values.sort((a, b) => b - a);
    }

    function refreshLabel(rate: real): string {
        return `${Number(rate).toFixed(Number(rate) % 1 === 0 ? 0 : 2)} Hz`;
    }

    function selectMonitor(m: var): void {
        selectedMonitor = m;
        const live = liveMonitorsByName[m?.name] ?? m;
        selectedResolution = currentResolutionLabel();
        selectedRefresh = Math.round((live?.refreshRate ?? 60) * 100) / 100;
        selectedScale = live?.scale ?? 1;
        selectedX = live?.x ?? 0;
        selectedY = live?.y ?? 0;
        selectedTransform = live?.transform ?? 0;
        selectedEnabled = true;
        mirrorFocused = false;
    }

    function resolutionWithRefresh(): string {
        if (selectedResolution === qsTr("Preferred") || selectedResolution === "preferred")
            return "preferred";
        const base = selectedResolution === qsTr("Current") ? currentResolutionLabel() : selectedResolution;
        return `${base}@${selectedRefresh}`;
    }

    function focusedMirrorPosition(): string {
        const focused = Hypr.focusedMonitor;
        if (!focused || !selectedMonitor || focused.name === selectedMonitor.name)
            return `${selectedX}x${selectedY}`;
        return `${focused.x}x${focused.y}`;
    }

    function applySelected(save: bool): void {
        if (!selectedMonitor)
            return;

        const live = liveMonitorsByName[selectedMonitor.name] ?? selectedMonitor;
        const oldRes = `${live.width}x${live.height}@${Math.round((live.refreshRate ?? 60) * 100) / 100}`;
        const oldPos = `${live.x}x${live.y}`;
        const oldScale = String(live.scale ?? 1);
        const pos = mirrorFocused ? focusedMirrorPosition() : `${selectedX}x${selectedY}`;

        saveAfterApply = save;
        monitorProc.exec([
            Quickshell.shellPath("modules/nexus/scripts/manage_monitors.py"),
            "--apply",
            "--name", selectedMonitor.name,
            "--res", selectedEnabled ? resolutionWithRefresh() : "disable",
            "--pos", pos,
            "--scale", String(selectedScale),
            "--transform", String(selectedTransform),
            "--old-res", oldRes,
            "--old-pos", oldPos,
            "--old-scale", oldScale
        ]);

    }

    function saveAll(): void {
        const monitorsData = Hypr.monitors.values.map(m => ({
            name: m.name,
            res: m.name === selectedMonitor?.name && selectedEnabled ? resolutionWithRefresh() : `${m.width}x${m.height}@${Math.round((m.refreshRate ?? 60) * 100) / 100}`,
            pos: m.name === selectedMonitor?.name ? (mirrorFocused ? focusedMirrorPosition() : `${selectedX}x${selectedY}`) : `${m.x}x${m.y}`,
            scale: m.name === selectedMonitor?.name ? selectedScale : m.scale,
            transform: m.name === selectedMonitor?.name ? selectedTransform : (m.transform ?? 0)
        }));
        saveProc.exec([Quickshell.shellPath("modules/nexus/scripts/manage_monitors.py"), "--save", "--monitors-json", JSON.stringify(monitorsData)]);
    }

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
                        const monitors = JSON.parse(text);
                        const modes = {};
                        const live = {};
                        for (const monitor of monitors) {
                            modes[monitor.name] = monitor.availableModes ?? [];
                            live[monitor.name] = monitor;
                        }
                        root.modesByMonitor = modes;
                        root.liveMonitorsByName = live;
                        const current = live[root.selectedMonitor?.name];
                        if (current) {
                            root.selectedResolution = `${current.width}x${current.height}`;
                            root.selectedRefresh = Math.round((current.refreshRate ?? 60) * 100) / 100;
                            root.selectedScale = current.scale ?? root.selectedScale;
                            root.selectedX = current.x ?? root.selectedX;
                            root.selectedY = current.y ?? root.selectedY;
                            root.selectedTransform = current.transform ?? root.selectedTransform;
                        }
                    } catch (error) {
                        root.statusMessage = qsTr("Could not read supported display modes");
                        root.statusIsError = true;
                    }
                }
            }
        }

        Process {
            id: policyStatusProc

            running: true
            command: ["caelestia-display", "status"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const state = JSON.parse(text);
                        root.pointerFollowsMonitor = state.pointerFollowsMonitor ?? true;
                        root.warpPointerWithWorkspace = state.warpPointerWithWorkspace ?? false;
                    } catch (error) {
                        root.statusMessage = qsTr("Could not read focus behaviour");
                        root.statusIsError = true;
                    }
                }
            }
        }

        Process {
            id: policyProc

            stdout: StdioCollector {
                onStreamFinished: {
                    const message = text.trim();
                    if (message)
                        root.statusMessage = message;
                }
            }
            stderr: StdioCollector {
                onStreamFinished: {
                    const message = text.trim();
                    if (message) {
                        root.statusMessage = message;
                        root.statusIsError = true;
                    }
                }
            }
            onExited: exitCode => {
                root.statusIsError = exitCode !== 0;
                policyStatusProc.running = true;
            }
        }

        Process {
            id: monitorProc

            stdout: StdioCollector {
                onStreamFinished: {
                    const message = text.trim();
                    if (message) {
                        root.statusMessage = message;
                        root.statusIsError = false;
                    }
                }
            }

            stderr: StdioCollector {
                onStreamFinished: {
                    const message = text.trim();
                    if (message) {
                        root.statusMessage = message;
                        root.statusIsError = true;
                    }
                }
            }

            onExited: exitCode => { // qmllint disable signal-handler-parameters
                if (exitCode === 0) {
                    if (!root.statusMessage)
                        root.statusMessage = qsTr("Display settings applied");
                    root.statusIsError = false;
                    if (root.saveAfterApply)
                        root.saveAll();
                } else {
                    if (!root.statusMessage)
                        root.statusMessage = qsTr("Display change failed and was rolled back");
                    root.statusIsError = true;
                }
                root.saveAfterApply = false;
                Qt.callLater(() => {
                    Hyprland.refreshMonitors();
                    modeProc.running = true;
                });
            }
        }

        Process {
            id: saveProc
            stdout: StdioCollector { onStreamFinished: { const message = text.trim(); if (message) root.statusMessage = message; } }
            stderr: StdioCollector { onStreamFinished: { const message = text.trim(); if (message) { root.statusMessage = message; root.statusIsError = true; } } }
            onExited: exitCode => {
                root.statusIsError = exitCode !== 0;
                if (exitCode === 0 && !root.statusMessage) root.statusMessage = qsTr("Display settings applied and saved");
            }
        }

        Component {
            id: monitorItem

            MenuItem {}
        }

        Component {
            id: modeItem

            MenuItem {}
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: false
            implicitHeight: preview.implicitHeight + preview.anchors.margins * 2

            Item {
                id: preview

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                implicitHeight: 240

                property real minX: Math.min(...Hypr.monitors.values.map(m => m.x), 0)
                property real minY: Math.min(...Hypr.monitors.values.map(m => m.y), 0)
                property real maxX: Math.max(...Hypr.monitors.values.map(m => m.x + m.width), 1920)
                property real maxY: Math.max(...Hypr.monitors.values.map(m => m.y + m.height), 1080)
                property real scaleFactor: Math.min(width / Math.max(1, maxX - minX), height / Math.max(1, maxY - minY)) * 0.8
                property real offsetX: (width - (maxX - minX) * scaleFactor) / 2
                property real offsetY: (height - (maxY - minY) * scaleFactor) / 2

                Repeater {
                    model: Hypr.monitors.values

                    delegate: Rectangle {
                        id: monRect

                        required property var modelData

                        x: (modelData.x - preview.minX) * preview.scaleFactor + preview.offsetX
                        y: (modelData.y - preview.minY) * preview.scaleFactor + preview.offsetY
                        width: Math.max(80, modelData.width * preview.scaleFactor)
                        height: Math.max(50, modelData.height * preview.scaleFactor)

                        color: root.selectedMonitor?.name === modelData.name ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainerHigh
                        border.color: root.selectedMonitor?.name === modelData.name ? Colours.palette.m3primary : Colours.palette.m3outlineVariant
                        border.width: 2
                        radius: Tokens.rounding.medium

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: parent.width - Tokens.padding.medium * 2
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: monRect.modelData.name
                                horizontalAlignment: Text.AlignHCenter
                                font: Tokens.font.body.medium
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: `${monRect.modelData.width}x${monRect.modelData.height}`
                                horizontalAlignment: Text.AlignHCenter
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            drag.target: monRect
                            drag.axis: Drag.XAndYAxis
                            cursorShape: Qt.PointingHandCursor
                            onPressed: root.selectMonitor(monRect.modelData)
                            onReleased: {
                                root.selectedX = Math.round(((monRect.x - preview.offsetX) / preview.scaleFactor + preview.minX) / 10) * 10;
                                root.selectedY = Math.round(((monRect.y - preview.offsetY) / preview.scaleFactor + preview.minY) / 10) * 10;
                            }
                        }
                    }
                }
            }
        }

        SectionHeader {
            text: qsTr("Monitor")
        }

        SelectRow {
            Layout.fillWidth: true
            first: true
            label: qsTr("Output")
            subtext: root.selectedMonitor?.description ?? qsTr("No monitor selected")
            menuItems: Hypr.monitors.values.map(m => monitorItem.createObject(root, {
                        text: m.name,
                        icon: root.selectedMonitor?.name === m.name ? "check" : "monitor"
                    }))
            active: Math.max(0, Hypr.monitors.values.findIndex(m => m.name === root.selectedMonitor?.name))
            fallbackText: root.selectedMonitor?.name ?? qsTr("Select")
            fallbackIcon: "monitor"
            onSelected: item => {
                const m = Hypr.monitors.values.find(mon => mon.name === item.text);
                if (m)
                    root.selectMonitor(m);
            }
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Enabled")
            subtext: qsTr("Disable only after another output is available")
            checked: root.selectedEnabled
            onToggled: root.selectedEnabled = checked
        }

        SelectRow {
            Layout.fillWidth: true
            label: qsTr("Resolution")
            subtext: qsTr("Modes reported by this display")
            menuItems: root.supportedResolutions().map(value => modeItem.createObject(root, { text: value }))
            active: Math.max(0, root.supportedResolutions().indexOf(root.selectedResolution))
            fallbackText: root.selectedResolution
            fallbackIcon: "aspect_ratio"
            onSelected: item => {
                root.selectedResolution = item.text;
                const rates = root.supportedRefreshRates();
                if (!rates.some(rate => Math.abs(rate - root.selectedRefresh) < 0.02))
                    root.selectedRefresh = rates[0] ?? root.selectedRefresh;
            }
        }

        SelectRow {
            Layout.fillWidth: true
            label: qsTr("Refresh rate")
            subtext: qsTr("Supported rates for the selected resolution")
            menuItems: root.supportedRefreshRates().map(rate => modeItem.createObject(root, { text: root.refreshLabel(rate) }))
            active: Math.max(0, root.supportedRefreshRates().findIndex(rate => Math.abs(rate - root.selectedRefresh) < 0.02))
            fallbackText: root.refreshLabel(root.selectedRefresh)
            fallbackIcon: "speed"
            onSelected: item => root.selectedRefresh = Number(item.text.replace(" Hz", ""))
        }

        SelectRow {
            Layout.fillWidth: true
            label: qsTr("Scale")
            subtext: qsTr("Text and UI size")
            menuItems: root.scaleItems
            active: root.scaleIndex(root.selectedScale)
            fallbackText: `${Math.round(root.selectedScale * 100)}%`
            fallbackIcon: "zoom_in"
            onSelected: item => {
                const values = [1, 1.25, 1.5, 1.75, 2];
                const index = root.scaleItems.findIndex(i => i.text === item.text);
                root.selectedScale = values[index] ?? 1;
            }
        }

        SelectRow {
            Layout.fillWidth: true
            last: true
            label: qsTr("Orientation")
            subtext: qsTr("Rotate this display")
            menuItems: root.orientationItems
            active: Math.max(0, Math.min(root.selectedTransform, root.orientationItems.length - 1))
            fallbackText: root.orientationItems[Math.max(0, Math.min(root.selectedTransform, root.orientationItems.length - 1))].text
            fallbackIcon: "screen_rotation"
            onSelected: item => root.selectedTransform = Math.max(0, root.orientationItems.findIndex(i => i.text === item.text))
        }

        SectionHeader {
            text: qsTr("Focus and workspaces")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Focus screen under pointer")
            subtext: qsTr("Keyboard focus follows the pointer between displays")
            checked: root.pointerFollowsMonitor
            onToggled: {
                root.pointerFollowsMonitor = checked;
                policyProc.exec(["caelestia-display", "policy", "pointer", checked ? "on" : "off"]);
            }
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Move pointer with workspace focus")
            subtext: qsTr("Keep mouse and keyboard control on the same display")
            checked: root.warpPointerWithWorkspace
            onToggled: {
                root.warpPointerWithWorkspace = checked;
                policyProc.exec(["caelestia-display", "policy", "warp", checked ? "on" : "off"]);
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            last: true
            implicitHeight: startupRow.implicitHeight + startupRow.anchors.margins * 2

            RowLayout {
                id: startupRow
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    StyledText {
                        text: qsTr("Startup display")
                        font: Tokens.font.body.medium
                    }
                    StyledText {
                        text: qsTr("Place the pointer and initial focus here after login")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
                TextButton {
                    text: qsTr("Use selected")
                    enabled: root.selectedMonitor !== null
                    onClicked: policyProc.exec(["caelestia-display", "primary", root.selectedMonitor.name])
                }
            }
        }

        SectionHeader {
            text: qsTr("Arrangement")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Mirror focused display")
            subtext: qsTr("Use the focused display position for this output")
            checked: root.mirrorFocused
            onToggled: root.mirrorFocused = checked
        }

        StepperRow {
            Layout.fillWidth: true
            label: qsTr("Horizontal position")
            subtext: qsTr("Pixels from layout origin")
            value: root.selectedX
            from: -10000
            to: 10000
            stepSize: 10
            enabled: !root.mirrorFocused
            onMoved: v => root.selectedX = v
        }

        StepperRow {
            Layout.fillWidth: true
            last: true
            label: qsTr("Vertical position")
            subtext: qsTr("Pixels from layout origin")
            value: root.selectedY
            from: -10000
            to: 10000
            stepSize: 10
            enabled: !root.mirrorFocused
            onMoved: v => root.selectedY = v
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: actionRow.implicitHeight + actionRow.anchors.margins * 2

            RowLayout {
                id: actionRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.fillWidth: true
                    text: root.statusMessage || qsTr("Choose a mode, then apply it now and keep it after reboot")
                    color: root.statusIsError ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.Wrap
                }

                TextButton {
                    text: qsTr("Apply & save")
                    onClicked: root.applySelected(true)
                }
            }
        }
    }

}
