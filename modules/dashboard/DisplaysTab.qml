pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    readonly property var monitor: Hypr.focusedMonitor ?? (Hypr.monitors.values[0] ?? null)
    readonly property var brightnessMonitor: Brightness.getMonitor("active")
    readonly property bool external: monitor && !monitor.name.startsWith("eDP-")
        && !monitor.name.startsWith("LVDS-") && !monitor.name.startsWith("DSI-")

    implicitWidth: 840
    implicitHeight: 492

    Component.onCompleted: MonitorControl.refresh()

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
                        ? qsTr("External monitor only · switches automatically")
                        : qsTr("Laptop display · connect a monitor to switch")
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
                            text: root.external ? qsTr("Automatic external-only") : qsTr("Automatic laptop-only")
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
                        icon: "brightness_6"
                        label: qsTr("Brightness")
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
}
