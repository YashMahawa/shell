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

    readonly property var monitor: Hypr.focusedMonitor ?? (Hypr.monitors.values[0] ?? null)
    readonly property var brightnessMonitor: Brightness.getMonitor("active")
    readonly property var laptopBrightnessMonitor: Brightness.getMonitor("eDP-1")
    readonly property bool external: monitor && !monitor.name.startsWith("eDP-")
        && !monitor.name.startsWith("LVDS-") && !monitor.name.startsWith("DSI-")
    property string displayMode: "external"
    property string pendingMode: ""
    property string pendingToken: ""
    property int revertSeconds: 0
    property string layoutMessage: ""
    property bool layoutError: false

    implicitWidth: 840
    implicitHeight: 620

    function applyMode(mode: string): void {
        if (pendingToken !== "" || modeProc.running)
            return;
        pendingMode = mode;
        layoutMessage = qsTr("Applying display layout safely…");
        layoutError = false;
        // Run the output transition outside Quickshell's service cgroup. The
        // worker cleanly stops the shell before a wl_output is removed and
        // starts it again on the final layout, avoiding Qt screen-destruction
        // crashes in External-only and Laptop-only modes.
        modeProc.exec(["caelestia-display-mode", mode]);
    }

    Component.onCompleted: {
        MonitorControl.refresh();
        statusProc.running = true;
    }

    Process {
        id: statusProc
        command: ["caelestia-display", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const state = JSON.parse(text);
                    root.displayMode = state.mode ?? "external";
                } catch (error) {
                    root.layoutError = true;
                }
            }
        }
    }

    Process {
        id: modeProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (result.saved) {
                        root.displayMode = result.profile ?? root.pendingMode;
                        root.pendingMode = "";
                        root.pendingToken = "";
                        root.revertSeconds = 0;
                        root.layoutMessage = qsTr("Display layout saved");
                        layoutRevertTimer.stop();
                        statusProc.running = true;
                        return;
                    }
                    root.pendingToken = result.token ?? "";
                    root.revertSeconds = result.timeout ?? 20;
                    root.layoutMessage = qsTr("Keep this layout within %1 seconds").arg(root.revertSeconds);
                    layoutRevertTimer.restart();
                } catch (error) {
                    root.layoutMessage = qsTr("Could not apply the display layout");
                    root.layoutError = true;
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim()) {
                    root.layoutMessage = text.trim();
                    root.layoutError = true;
                }
            }
        }
        onExited: Hyprland.refreshMonitors()
    }

    Process {
        id: confirmModeProc
        onExited: {
            root.displayMode = root.pendingMode;
            root.pendingMode = "";
            root.pendingToken = "";
            root.layoutMessage = qsTr("Display layout saved");
            layoutRevertTimer.stop();
            statusProc.running = true;
            Hyprland.refreshMonitors();
        }
    }

    Process {
        id: moveWindowProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim()) {
                    root.layoutMessage = text.trim();
                    root.layoutError = false;
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim()) {
                    root.layoutMessage = text.trim();
                    root.layoutError = true;
                }
            }
        }
    }

    Timer {
        id: layoutRevertTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.revertSeconds--;
            if (root.revertSeconds <= 0) {
                stop();
                root.pendingToken = "";
                root.pendingMode = "";
                root.layoutMessage = qsTr("Previous display layout restored");
                statusProc.running = true;
                Hyprland.refreshMonitors();
            } else {
                root.layoutMessage = qsTr("Keep this layout within %1 seconds").arg(root.revertSeconds);
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
                    text: qsTr("Display")
                    font: Tokens.font.title.large
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    text: root.external
                        ? qsTr("Choose how the laptop and external display work together")
                        : qsTr("Connect an external display for multi-display modes")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            Item { Layout.fillWidth: true }

            TextButton {
                text: qsTr("All settings")
                onClicked: Quickshell.execDetached(["caelestia", "shell", "nexus", "openDisplay"])
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.extraSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                ModeButton { mode: "extend"; label: qsTr("Join"); icon: "view_week" }
                ModeButton { mode: "mirror"; label: qsTr("Mirror"); icon: "content_copy" }
                ModeButton { mode: "external"; label: qsTr("External"); icon: "desktop_windows" }
                ModeButton { mode: "laptop"; label: qsTr("Laptop"); icon: "laptop" }

                TextButton {
                    visible: root.pendingToken !== ""
                    text: qsTr("Keep")
                    onClicked: confirmModeProc.exec([
                        "caelestia-display", "confirm", root.pendingToken
                    ])
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.displayMode === "extend"
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Move focused window")
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onSurfaceVariant
                }

                ActionButton {
                    label: qsTr("To laptop")
                    icon: "laptop"
                    onTriggered: moveWindowProc.exec([
                        "caelestia-display", "move-window", "eDP-1"
                    ])
                }

                ActionButton {
                    label: qsTr("To external")
                    icon: "desktop_windows"
                    onTriggered: moveWindowProc.exec([
                        "caelestia-display", "move-window", "HDMI-A-1"
                    ])
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.layoutMessage !== ""
                text: root.layoutMessage
                color: root.layoutError
                    ? Colours.palette.m3error
                    : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                elide: Text.ElideRight
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
                Layout.preferredWidth: 0.9
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    Item { Layout.fillHeight: true }

                    StyledRect {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 220
                        implicitHeight: 126
                        radius: Tokens.rounding.large
                        color: Colours.palette.m3primaryContainer
                        border.width: 2
                        border.color: Colours.palette.m3primary

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: parent.width - Tokens.padding.large * 2
                            spacing: Tokens.spacing.extraSmall

                            MaterialIcon {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.external ? "desktop_windows" : "laptop"
                                fontStyle: Tokens.font.icon.large
                                color: Colours.palette.m3primary
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: MonitorControl.available
                                    ? MonitorControl.model
                                    : (root.monitor?.description ?? root.monitor?.name ?? qsTr("Display"))
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                font: Tokens.font.title.small
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.monitor
                                    ? `${root.monitor.width}×${root.monitor.height} · ${Math.round(root.monitor.refreshRate ?? 60)} Hz`
                                    : qsTr("Waiting for display")
                                horizontalAlignment: Text.AlignHCenter
                                font: Tokens.font.label.small
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Tokens.spacing.small
                        MaterialIcon {
                            text: "sync"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3primary
                        }
                        StyledText {
                            text: ({
                                extend: qsTr("Joined displays"),
                                mirror: qsTr("Mirrored displays"),
                                external: qsTr("External display only"),
                                laptop: qsTr("Laptop display only")
                            })[root.displayMode] ?? qsTr("Display layout")
                            font: Tokens.font.label.medium
                            color: Colours.palette.m3primary
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1.35
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    RowLayout {
                        Layout.fillWidth: true

                        StyledText {
                            text: qsTr("Quick controls")
                            font: Tokens.font.title.small
                        }
                        Item { Layout.fillWidth: true }
                        MaterialIcon {
                            text: MonitorControl.available ? "check_circle" : "info"
                            fontStyle: Tokens.font.icon.small
                            color: MonitorControl.available
                                ? Colours.palette.m3primary
                                : Colours.palette.m3onSurfaceVariant
                        }
                    }

                    ControlSlider {
                        icon: "laptop"
                        label: qsTr("Laptop brightness")
                        value: root.laptopBrightnessMonitor?.brightness ?? 0
                        enabled: root.laptopBrightnessMonitor !== null
                        onMoved: value => root.laptopBrightnessMonitor?.setBrightness(value)
                    }

                    ControlSlider {
                        icon: "brightness_6"
                        label: qsTr("Focused display brightness")
                        value: root.brightnessMonitor?.brightness ?? 0
                        enabled: root.brightnessMonitor !== null
                        onMoved: value => root.brightnessMonitor?.setBrightness(value)
                    }

                    ControlSlider {
                        icon: "contrast"
                        label: qsTr("Contrast")
                        value: MonitorControl.contrast / 100
                        enabled: MonitorControl.available
                        onMoved: value => MonitorControl.setControl("contrast", Math.round(value * 100))
                    }

                    ControlSlider {
                        icon: MonitorControl.muted ? "volume_off" : "volume_up"
                        label: qsTr("Monitor speakers")
                        value: MonitorControl.volume / 100
                        enabled: MonitorControl.available
                        onMoved: value => MonitorControl.setControl("volume", Math.round(value * 100))
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        InputButton {
                            Layout.fillWidth: true
                            label: "HDMI 1"
                            inputName: "hdmi1"
                        }
                        InputButton {
                            Layout.fillWidth: true
                            label: "HDMI 2"
                            inputName: "hdmi2"
                        }
                        InputButton {
                            Layout.fillWidth: true
                            label: "DP"
                            inputName: "displayport"
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: !MonitorControl.available
                        text: MonitorControl.busy
                            ? qsTr("Reading monitor controls…")
                            : (MonitorControl.errorMessage || qsTr("DDC/CI controls require a compatible monitor"))
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }

    component ControlSlider: ColumnLayout {
        id: control

        required property string icon
        required property string label
        property real value: 0
        signal moved(real value)

        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        RowLayout {
            Layout.fillWidth: true
            MaterialIcon {
                text: control.icon
                fontStyle: Tokens.font.icon.small
                color: Colours.palette.m3primary
            }
            StyledText {
                Layout.fillWidth: true
                text: control.label
                font: Tokens.font.body.small
            }
            StyledText {
                text: `${Math.round(control.value * 100)}%`
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }

        StyledSlider {
            Layout.fillWidth: true
            value: control.value
            enabled: control.enabled
            onInteraction: value => control.moved(value)
        }
    }

    component InputButton: StyledRect {
        id: inputButton

        required property string label
        required property string inputName

        implicitHeight: 38
        radius: Tokens.rounding.medium
        color: MonitorControl.input === inputName
            ? Colours.palette.m3primaryContainer
            : Colours.tPalette.m3surfaceContainerHigh
        border.width: MonitorControl.input === inputName ? 1 : 0
        border.color: Colours.palette.m3primary
        opacity: MonitorControl.available ? 1 : 0.45

        StyledText {
            anchors.centerIn: parent
            text: inputButton.label
            font: Tokens.font.label.medium
            color: MonitorControl.input === inputButton.inputName
                ? Colours.palette.m3primary
                : Colours.palette.m3onSurface
        }
        StateLayer {
            anchors.fill: parent
            radius: inputButton.radius
            enabled: MonitorControl.available
            color: Colours.palette.m3primary
            onClicked: MonitorControl.setControl("input", inputButton.inputName)
        }
    }

    component ModeButton: StyledRect {
        id: modeButton

        required property string mode
        required property string label
        required property string icon
        readonly property bool selected: root.pendingToken !== ""
            ? root.pendingMode === mode
            : root.displayMode === mode

        Layout.fillWidth: true
        implicitHeight: 42
        radius: Tokens.rounding.medium
        color: selected
            ? Colours.palette.m3primaryContainer
            : Colours.tPalette.m3surfaceContainerHigh
        border.width: selected ? 1 : 0
        border.color: Colours.palette.m3primary
        opacity: modeProc.running && root.pendingMode !== mode ? 0.55 : 1

        RowLayout {
            anchors.centerIn: parent
            spacing: Tokens.spacing.extraSmall

            MaterialIcon {
                text: modeButton.icon
                fontStyle: Tokens.font.icon.small
                color: modeButton.selected
                    ? Colours.palette.m3primary
                    : Colours.palette.m3onSurfaceVariant
            }
            StyledText {
                text: modeButton.label
                font: Tokens.font.label.medium
                color: modeButton.selected
                    ? Colours.palette.m3primary
                    : Colours.palette.m3onSurface
            }
        }

        StateLayer {
            anchors.fill: parent
            radius: modeButton.radius
            enabled: root.pendingToken === "" && !modeProc.running
            color: Colours.palette.m3primary
            onClicked: root.applyMode(modeButton.mode)
        }
    }

    component ActionButton: StyledRect {
        id: actionButton

        required property string label
        required property string icon
        signal triggered()

        implicitWidth: actionContent.implicitWidth + Tokens.padding.large * 2
        implicitHeight: 34
        radius: Tokens.rounding.medium
        color: Colours.tPalette.m3surfaceContainerHigh

        RowLayout {
            id: actionContent
            anchors.centerIn: parent
            spacing: Tokens.spacing.extraSmall

            MaterialIcon {
                text: actionButton.icon
                fontStyle: Tokens.font.icon.small
                color: Colours.palette.m3primary
            }
            StyledText {
                text: actionButton.label
                font: Tokens.font.label.medium
            }
        }

        StateLayer {
            anchors.fill: parent
            radius: actionButton.radius
            enabled: !moveWindowProc.running
            color: Colours.palette.m3primary
            onClicked: actionButton.triggered()
        }
    }
}
