pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services

Scope {
    id: root

    property string status: "idle"
    property string message: ""
    property string detail: ""
    readonly property bool active: status !== "idle" && status !== ""

    FileView {
        id: stateFile
        path: "/home/yash/.local/state/caelestia/voice-state.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const state = JSON.parse(text());
                root.status = state.status ?? "idle";
                root.message = state.message ?? "";
                root.detail = state.detail ?? "";
            } catch (error) {
                root.status = "idle";
            }
        }
    }

    Variants {
        model: Screens.screens

        StyledWindow {
            required property ShellScreen modelData
            screen: modelData
            name: "voice-typing"
            visible: root.active && (Hypr.focusedMonitor?.name ?? modelData.name) === modelData.name
            implicitWidth: 520
            implicitHeight: 84
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors.top: true
            margins.top: 28

            StyledRect {
                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                radius: Tokens.rounding.full
                color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 1)
                border.width: 1
                border.color: root.status === "error" ? Colours.palette.m3error : Colours.palette.m3primary

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.large
                    anchors.rightMargin: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.status === "processing" ? "progress_activity" : root.status === "done" ? "check_circle" : root.status === "error" ? "error" : "mic"
                        color: root.status === "error" ? Colours.palette.m3error : Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.large
                        RotationAnimation on rotation {
                            running: root.status === "processing"
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 900
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 72

                        StyledText {
                            text: root.message
                            font: Tokens.font.body.builders.large.weight(Font.Medium).build()
                        }
                        StyledText {
                            visible: text.length > 0
                            width: parent.width
                            text: root.detail
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
