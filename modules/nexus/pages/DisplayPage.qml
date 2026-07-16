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
    property string selectedResolution: "preferred"
    property real selectedRefresh: Math.round((selectedMonitor?.refreshRate ?? 60000) / 1000)
    property real selectedScale: selectedMonitor?.scale ?? 1
    property int selectedX: selectedMonitor?.x ?? 0
    property int selectedY: selectedMonitor?.y ?? 0
    property int selectedTransform: selectedMonitor?.transform ?? 0
    property bool selectedEnabled: true
    property bool mirrorFocused: false
    property bool showConfirmSave: false
    property string statusMessage: ""
    property bool statusIsError: false

    readonly property list<MenuItem> resolutionItems: [
        MenuItem {
            text: qsTr("Preferred")
        },
        MenuItem {
            text: root.currentResolutionLabel()
        },
        MenuItem {
            text: "3840x2160"
        },
        MenuItem {
            text: "2560x1600"
        },
        MenuItem {
            text: "2560x1440"
        },
        MenuItem {
            text: "1920x1200"
        },
        MenuItem {
            text: "1920x1080"
        },
        MenuItem {
            text: "1600x900"
        },
        MenuItem {
            text: "1366x768"
        },
        MenuItem {
            text: "1280x720"
        }
    ]
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
        const m = selectedMonitor;
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

    function selectMonitor(m: var): void {
        selectedMonitor = m;
        selectedResolution = currentResolutionLabel();
        selectedRefresh = Math.round((m?.refreshRate ?? 60000) / 1000);
        selectedScale = m?.scale ?? 1;
        selectedX = m?.x ?? 0;
        selectedY = m?.y ?? 0;
        selectedTransform = m?.transform ?? 0;
        selectedEnabled = true;
        mirrorFocused = false;
        showConfirmSave = false;
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

        const oldRes = `${selectedMonitor.width}x${selectedMonitor.height}@${Math.round((selectedMonitor.refreshRate ?? 60000) / 1000)}`;
        const oldPos = `${selectedMonitor.x}x${selectedMonitor.y}`;
        const oldScale = String(selectedMonitor.scale ?? 1);
        const pos = mirrorFocused ? focusedMirrorPosition() : `${selectedX}x${selectedY}`;

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

        if (save)
            saveAll();
    }

    function saveAll(): void {
        const monitorsData = Hypr.monitors.values.map(m => ({
            name: m.name,
            res: m.name === selectedMonitor?.name && selectedEnabled ? resolutionWithRefresh() : `${m.width}x${m.height}@${Math.round((m.refreshRate ?? 60000) / 1000)}`,
            pos: m.name === selectedMonitor?.name ? (mirrorFocused ? focusedMirrorPosition() : `${selectedX}x${selectedY}`) : `${m.x}x${m.y}`,
            scale: m.name === selectedMonitor?.name ? selectedScale : m.scale,
            transform: m.name === selectedMonitor?.name ? selectedTransform : (m.transform ?? 0)
        }));
        monitorProc.exec([Quickshell.shellPath("modules/nexus/scripts/manage_monitors.py"), "--save", "--monitors-json", JSON.stringify(monitorsData)]);
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

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
                    Hypr.dispatch("reload");
                } else {
                    if (!root.statusMessage)
                        root.statusMessage = qsTr("Display change failed and was rolled back");
                    root.statusIsError = true;
                }
                Qt.callLater(() => {
                    Hyprland.refreshMonitors();
                });
            }
        }

        Component {
            id: monitorItem

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
            subtext: qsTr("Choose preferred or a common fixed mode")
            menuItems: root.resolutionItems
            active: Math.max(0, root.resolutionItems.findIndex(i => i.text === root.selectedResolution))
            fallbackText: root.selectedResolution
            fallbackIcon: "aspect_ratio"
            onSelected: item => root.selectedResolution = item.text
        }

        StepperRow {
            Layout.fillWidth: true
            label: qsTr("Refresh rate")
            subtext: qsTr("Hz")
            value: root.selectedRefresh
            from: 24
            to: 240
            stepSize: 1
            onMoved: v => root.selectedRefresh = v
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
                    text: root.statusMessage || qsTr("Preview changes before saving them")
                    color: root.statusIsError ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.Wrap
                }

                TextButton {
                    text: qsTr("Apply")
                    onClicked: root.applySelected(false)
                }

                TextButton {
                    text: root.showConfirmSave ? qsTr("Confirm") : qsTr("Save")
                    onClicked: {
                        if (!root.showConfirmSave) {
                            root.showConfirmSave = true;
                            root.statusMessage = qsTr("Save this monitor layout to Hyprland config?");
                            root.statusIsError = false;
                        } else {
                            root.applySelected(true);
                            root.showConfirmSave = false;
                        }
                    }
                }
            }
        }
    }

}
