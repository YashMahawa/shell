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

Item {
    id: root

    property var selectedMonitor: Hypr.focusedMonitor ?? (Hypr.monitors.values[0] ?? null)
    property bool pointerFollowsMonitor: true
    property bool warpPointerWithWorkspace: false
    property string pendingToken: ""
    property int revertSeconds: 0
    property string message: ""
    property bool error: false

    readonly property var monitors: Hypr.monitors.values
    readonly property bool hasExternal: monitors.some(m => !m.name.startsWith("eDP-") && !m.name.startsWith("LVDS-") && !m.name.startsWith("DSI-"))

    implicitWidth: 840
    implicitHeight: 492

    function run(args: var): void {
        root.message = "";
        root.error = false;
        actionProc.exec(["caelestia-display"].concat(args));
    }

    function refresh(): void {
        statusProc.running = true;
        Hyprland.refreshMonitors();
    }

    Component.onCompleted: refresh()

    Process {
        id: statusProc
        command: ["caelestia-display", "status"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const state = JSON.parse(text);
                    root.pointerFollowsMonitor = state.pointerFollowsMonitor ?? true;
                    root.warpPointerWithWorkspace = state.warpPointerWithWorkspace ?? false;
                    const current = root.monitors.find(m => m.name === state.focused);
                    if (current)
                        root.selectedMonitor = current;
                } catch (e) {
                    root.message = qsTr("Display status is temporarily unavailable");
                    root.error = true;
                }
            }
        }
    }

    Process {
        id: actionProc

        stdout: StdioCollector {
            onStreamFinished: {
                const output = text.trim();
                if (!output)
                    return;
                try {
                    const result = JSON.parse(output);
                    if (result.token) {
                        root.pendingToken = result.token;
                        root.revertSeconds = result.timeout ?? 20;
                        root.message = qsTr("Keep this layout within %1 seconds").arg(root.revertSeconds);
                        revertTimer.restart();
                    }
                } catch (e) {
                    root.message = output;
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const output = text.trim();
                if (output) {
                    root.message = output;
                    root.error = true;
                }
            }
        }

        onExited: exitCode => {
            root.error = exitCode !== 0;
            root.refresh();
        }
    }

    Timer {
        id: revertTimer
        interval: 1000
        repeat: true
        running: false
        onTriggered: {
            root.revertSeconds--;
            if (root.revertSeconds <= 0) {
                stop();
                root.pendingToken = "";
                root.message = qsTr("Previous display layout restored");
                root.refresh();
            } else {
                root.message = qsTr("Keep this layout within %1 seconds").arg(root.revertSeconds);
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large

            ColumnLayout {
                spacing: 1

                StyledText {
                    text: qsTr("Displays")
                    font: Tokens.font.title.large
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    text: root.monitors.length > 1
                        ? qsTr("%1 screens connected").arg(root.monitors.length)
                        : qsTr("Laptop screen only")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            Item { Layout.fillWidth: true }

            TextButton {
                text: qsTr("Display settings")
                onClicked: Quickshell.execDetached(["caelestia", "shell", "nexus", "openDisplay"])
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.medium

            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1.3
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    RowLayout {
                        Layout.fillWidth: true

                        StyledText {
                            text: qsTr("Arrangement")
                            font: Tokens.font.title.small
                        }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            text: root.selectedMonitor?.name ?? ""
                            font: Tokens.font.label.small
                            color: Colours.palette.m3primary
                        }
                    }

                    Item {
                        id: preview
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 150

                        property real minX: Math.min(...root.monitors.map(m => m.x), 0)
                        property real minY: Math.min(...root.monitors.map(m => m.y), 0)
                        property real maxX: Math.max(...root.monitors.map(m => m.x + m.width / Math.max(m.scale, 0.25)), 1920)
                        property real maxY: Math.max(...root.monitors.map(m => m.y + m.height / Math.max(m.scale, 0.25)), 1080)
                        property real factor: Math.min(width / Math.max(1, maxX - minX), height / Math.max(1, maxY - minY)) * 0.82

                        Repeater {
                            model: root.monitors

                            delegate: StyledRect {
                                id: screen
                                required property var modelData

                                x: (modelData.x - preview.minX) * preview.factor + (preview.width - (preview.maxX - preview.minX) * preview.factor) / 2
                                y: (modelData.y - preview.minY) * preview.factor + (preview.height - (preview.maxY - preview.minY) * preview.factor) / 2
                                width: Math.max(112, modelData.width / Math.max(modelData.scale, 0.25) * preview.factor)
                                height: Math.max(66, modelData.height / Math.max(modelData.scale, 0.25) * preview.factor)
                                radius: Tokens.rounding.medium
                                color: root.selectedMonitor?.name === modelData.name
                                    ? Colours.palette.m3primaryContainer
                                    : Colours.tPalette.m3surfaceContainerHigh
                                border.width: 2
                                border.color: root.selectedMonitor?.name === modelData.name
                                    ? Colours.palette.m3primary
                                    : Colours.palette.m3outlineVariant

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    width: parent.width - Tokens.padding.medium * 2
                                    spacing: 0

                                    MaterialIcon {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: screen.modelData.name.startsWith("eDP-") ? "laptop" : "desktop_windows"
                                        fontStyle: Tokens.font.icon.medium
                                        color: root.selectedMonitor?.name === screen.modelData.name
                                            ? Colours.palette.m3primary
                                            : Colours.palette.m3onSurfaceVariant
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: screen.modelData.name
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        font: Tokens.font.label.medium
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: {
                                            const rate = screen.modelData.lastIpcObject?.refreshRate ?? screen.modelData.refreshRate ?? 0;
                                            return `${screen.modelData.width}x${screen.modelData.height}  ${Math.round(rate)} Hz`;
                                        }
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3onSurfaceVariant
                                    }
                                }

                                StateLayer {
                                    anchors.fill: parent
                                    radius: screen.radius
                                    color: Colours.palette.m3primary
                                    onClicked: root.selectedMonitor = screen.modelData
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        ActionButton {
                            Layout.fillWidth: true
                            icon: "mouse"
                            label: qsTr("Control screen")
                            enabled: root.selectedMonitor !== null
                            onClicked: root.run(["focus", root.selectedMonitor.name])
                        }
                        ActionButton {
                            Layout.fillWidth: true
                            icon: "drive_file_move"
                            label: qsTr("Move workspace")
                            enabled: root.selectedMonitor !== null
                            onClicked: root.run(["move-workspace", root.selectedMonitor.name])
                        }
                        ActionButton {
                            Layout.fillWidth: true
                            icon: "move_up"
                            label: qsTr("Move window")
                            enabled: root.selectedMonitor !== null
                            onClicked: root.run(["move-window", root.selectedMonitor.name])
                        }
                    }
                }
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 0.8
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: qsTr("Display mode")
                        font: Tokens.font.title.small
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.hasExternal
                            ? qsTr("Choose what appears on each screen")
                            : qsTr("Connect a monitor to unlock display profiles")
                        wrapMode: Text.Wrap
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    ProfileButton {
                        icon: "view_carousel"
                        label: qsTr("Extend")
                        description: qsTr("Independent workspaces on both screens")
                        enabled: root.hasExternal
                        onClicked: root.run(["mode", "extend"])
                    }
                    ProfileButton {
                        icon: "content_copy"
                        label: qsTr("Mirror")
                        description: qsTr("Show the same content")
                        enabled: root.hasExternal
                        onClicked: root.run(["mode", "mirror"])
                    }
                    ProfileButton {
                        icon: "laptop"
                        label: qsTr("Laptop only")
                        description: qsTr("Turn off external displays")
                        enabled: root.hasExternal
                        onClicked: root.run(["mode", "laptop"])
                    }
                    ProfileButton {
                        icon: "desktop_windows"
                        label: qsTr("External only")
                        description: qsTr("Turn off the laptop screen")
                        enabled: root.hasExternal
                        onClicked: root.run(["mode", "external"])
                    }

                    Item { Layout.fillHeight: true }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.pendingToken !== ""

                        StyledText {
                            Layout.fillWidth: true
                            text: root.message
                            color: Colours.palette.m3primary
                            font: Tokens.font.label.small
                        }
                        TextButton {
                            text: qsTr("Keep")
                            onClicked: {
                                root.run(["confirm", root.pendingToken]);
                                root.pendingToken = "";
                                revertTimer.stop();
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.message !== "" && root.pendingToken === ""
                        text: root.message
                        color: root.error ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                        wrapMode: Text.Wrap
                        font: Tokens.font.label.small
                    }
                }
            }
        }
    }

    component ActionButton: StyledRect {
        id: action
        required property string icon
        required property string label
        signal clicked

        implicitHeight: 44
        radius: Tokens.rounding.medium
        color: Colours.tPalette.m3surfaceContainerHigh
        opacity: enabled ? 1 : 0.45

        Row {
            anchors.centerIn: parent
            spacing: Tokens.spacing.small
            MaterialIcon {
                text: action.icon
                fontStyle: Tokens.font.icon.small
                color: Colours.palette.m3primary
            }
            StyledText {
                text: action.label
                font: Tokens.font.label.small
            }
        }
        StateLayer {
            anchors.fill: parent
            radius: action.radius
            enabled: action.enabled
            color: Colours.palette.m3primary
            onClicked: action.clicked()
        }
    }

    component ProfileButton: StyledRect {
        id: profile
        required property string icon
        required property string label
        required property string description
        signal clicked

        Layout.fillWidth: true
        implicitHeight: 58
        radius: Tokens.rounding.medium
        color: Colours.tPalette.m3surfaceContainerHigh
        opacity: enabled ? 1 : 0.4

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: profile.icon
                fontStyle: Tokens.font.icon.medium
                color: Colours.palette.m3primary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: profile.label
                    font: Tokens.font.label.medium
                }
                StyledText {
                    Layout.fillWidth: true
                    text: profile.description
                    elide: Text.ElideRight
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
            MaterialIcon {
                text: "chevron_right"
                fontStyle: Tokens.font.icon.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }
        StateLayer {
            anchors.fill: parent
            radius: profile.radius
            enabled: profile.enabled
            color: Colours.palette.m3primary
            onClicked: profile.clicked()
        }
    }
}
