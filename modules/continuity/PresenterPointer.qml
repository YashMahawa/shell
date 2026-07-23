import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.services

Scope {
    id: root

    property bool pointerVisible: false
    property real pointerX: 0.5
    property real pointerY: 0.5

    FileView {
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/caelestia-presenter-pointer.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const state = JSON.parse(text());
                root.pointerVisible = state.visible === true;
                root.pointerX = Math.max(0, Math.min(1, Number(state.x ?? 0.5)));
                root.pointerY = Math.max(0, Math.min(1, Number(state.y ?? 0.5)));
            } catch (error) {
                root.pointerVisible = false;
            }
        }
    }

    Variants {
        model: Screens.screens

        PanelWindow {
            id: overlay
            required property ShellScreen modelData

            screen: modelData
            visible: root.pointerVisible && (Hypr.focusedMonitor?.name ?? modelData.name) === modelData.name
            color: "transparent"
            mask: Region {}

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors { top: true; right: true; bottom: true; left: true }

            StyledRect {
                width: 18
                height: 18
                radius: 9
                color: "#e04747"
                border.width: 2
                border.color: "#f7f3ef"
                x: root.pointerX * (overlay.width - width)
                y: root.pointerY * (overlay.height - height)

                Behavior on x { NumberAnimation { duration: 34; easing.type: Easing.OutQuad } }
                Behavior on y { NumberAnimation { duration: 34; easing.type: Easing.OutQuad } }
            }
        }
    }
}
