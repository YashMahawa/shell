pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services

Scope {
    id: root
    property bool sent: false

    Timer {
        id: sentTimer
        interval: 1800
        onTriggered: root.sent = false
    }

    Variants {
        model: Screens.screens

        StyledWindow {
            id: window
            required property ShellScreen modelData

            screen: modelData
            name: "continuity-island"
            visible: true
            implicitWidth: 520
            implicitHeight: 128
            color: "transparent"
            mask: Region {
                width: window.width
                height: drop.containsDrag || root.sent ? window.height : 16
            }

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors.top: true
            margins.top: -3

            StyledRect {
                id: bubble
                anchors.horizontalCenter: parent.horizontalCenter
                y: 18
                width: 440
                height: 86
                radius: 28
                opacity: drop.containsDrag || root.sent ? 1 : 0
                scale: drop.containsDrag || root.sent ? 1 : 0.92
                color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 0.98)
                border.width: 1
                border.color: drop.containsDrag ? Colours.palette.m3primary : Colours.layer(Colours.palette.m3outline, 0.35)

                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                Row {
                    anchors.centerIn: parent
                    spacing: 10

                    MaterialIcon {
                        text: root.sent ? "check_circle" : "ios_share"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.large
                        renderType: Text.NativeRendering
                    }
                    StyledText {
                        text: root.sent ? qsTr("Sent to T2 5G") : qsTr("Drop to share with T2 5G")
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.title.medium
                    }
                }

            }

            DropArea {
                id: drop
                anchors.fill: parent
                onDropped: event => {
                    const values = [];
                    for (const url of event.urls ?? [])
                        values.push(String(url));
                    if (values.length) {
                        Quickshell.execDetached(["caelestia-clipboard", "send-path", ...values]);
                        root.sent = true;
                        sentTimer.restart();
                    }
                    event.acceptProposedAction();
                }
            }
        }
    }
}
