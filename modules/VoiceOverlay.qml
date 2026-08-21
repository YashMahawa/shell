pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.utils

Scope {
    id: root

    property string status: "idle"
    property string message: ""
    property string detail: ""
    readonly property bool active: status !== "idle" && status !== ""

    FileView {
        id: stateFile
        path: `${Paths.state}/voice-state.json`
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
                color: Colours.layer(
                    Colours.palette.m3surfaceContainerHigh,
                    TrueLite.effectsEnabled ? 0.72 : 0.96
                )
                border.width: 1
                border.color: Colours.layer(
                    root.status === "error" ? Colours.palette.m3error : Colours.palette.m3primary,
                    0.72
                )

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.large
                    anchors.rightMargin: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: 38
                        implicitHeight: 38

                        StyledRect {
                            anchors.fill: parent
                            radius: width / 2
                            color: root.status === "error" ? Colours.palette.m3errorContainer : Colours.palette.m3primaryContainer
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: root.status !== "processing"
                            rotation: 0
                            text: root.status === "done" ? "check" : root.status === "error" ? "error" : "mic"
                            color: root.status === "error" ? Colours.palette.m3onErrorContainer : Colours.palette.m3onPrimaryContainer
                            fontStyle: Tokens.font.icon.medium
                            renderType: Text.NativeRendering
                        }

                        Row {
                            anchors.centerIn: parent
                            visible: root.status === "processing"
                            spacing: 3

                            Repeater {
                                model: 3

                                StyledRect {
                                    required property int index
                                    width: 4
                                    height: 4
                                    radius: 2
                                    color: Colours.palette.m3onPrimaryContainer

                                    SequentialAnimation on opacity {
                                        running: root.status === "processing"
                                        loops: Animation.Infinite
                                        PauseAnimation { duration: index * 130 }
                                        NumberAnimation { from: 0.35; to: 1; duration: 220 }
                                        NumberAnimation { from: 1; to: 0.35; duration: 220 }
                                        PauseAnimation { duration: (2 - index) * 130 }
                                    }
                                }
                            }
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
