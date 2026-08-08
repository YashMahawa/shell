pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components.containers
import qs.components.misc
import qs.services

Scope {
    Variants {
        model: Screens.screens

        StyledWindow {
            id: window

            required property ShellScreen modelData
            readonly property bool isTarget: !ImmersiveLyricsState.screenName || ImmersiveLyricsState.screenName === modelData.name

            screen: modelData
            name: "immersive-lyrics"
            color: "transparent"
            // The native static backdrop is a separate layer below this
            // foreground, so this surface must preserve transparency.
            surfaceFormat.opaque: false
            visible: ImmersiveLyricsState.active && isTarget
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            onVisibleChanged: {
                if (visible)
                    Qt.callLater(() => surface.item?.forceActiveFocus());
            }

            Loader {
                id: surface

                anchors.fill: parent
                active: window.visible
                asynchronous: true
                onLoaded: {
                    if (window.visible)
                        item?.forceActiveFocus();
                }
                sourceComponent: ImmersiveSurface {
                    active: ImmersiveLyricsState.presented
                    onExitRequested: ImmersiveLyricsState.close()
                }
            }
        }
    }

    IpcHandler {
        function open(screenName: string): void {
            ImmersiveLyricsState.open(screenName);
        }

        function close(): void {
            ImmersiveLyricsState.close();
        }

        function toggle(screenName: string): void {
            ImmersiveLyricsState.toggle(screenName);
        }

        target: "immersiveLyrics"
    }

    CustomShortcut {
        name: "immersiveLyrics"
        description: "Toggle immersive lyrics"
        onPressed: ImmersiveLyricsState.toggle(Hypr.focusedMonitor?.name ?? "")
    }
}
