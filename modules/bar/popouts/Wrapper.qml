pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus
import qs.modules.windowinfo
import qs.modules.continuity as ContinuityModule
import qs.modules.calendar as CalendarModule

Item {
    id: root

    required property ShellScreen screen
    required property real offsetScale

    readonly property alias content: content
    readonly property alias winfo: winfo
    readonly property alias nexus: nexus

    readonly property real nonAnimWidth: children.find(c => c.shouldBeActive)?.implicitWidth ?? content.implicitWidth
    readonly property real nonAnimHeight: children.find(c => c.shouldBeActive)?.implicitHeight ?? content.implicitHeight
    readonly property Item current: (content.item as Content)?.current ?? null
    readonly property bool isDetached: detachedMode.length > 0

    property alias currentName: popoutState.currentName
    property alias hasCurrent: popoutState.hasCurrent
    property alias sticky: popoutState.sticky
    property real currentCenter

    property string detachedMode
    property string queuedMode
    property string linkPage: "overview"
    property string calendarPage: "calendar"
    property HyprlandToplevel windowInfoClient: null

    function selectWindowInfoClientAt(globalX: real, globalY: real): void {
        if (detachedMode !== "winfo")
            return;

        const monitor = Hypr.monitors.values.find(mon => {
            const scale = Math.max(mon.scale ?? 1, 0.25);
            const width = (mon.width ?? 0) / scale;
            const height = (mon.height ?? 0) / scale;
            return globalX >= mon.x && globalX < mon.x + width
                && globalY >= mon.y && globalY < mon.y + height;
        });
        if (!monitor)
            return;

        const special = monitor.lastIpcObject.specialWorkspace;
        const workspaceId = special?.name ? special.id : monitor.activeWorkspace?.id;
        const candidates = Hypr.toplevels.values.filter(client => {
            const data = client?.lastIpcObject;
            if (!data)
                return false;
            const visible = client.workspace?.id === workspaceId
                || (data.pinned && client.monitor?.id === monitor.id);
            if (!visible)
                return false;
            const x = data.at?.[0] ?? 0;
            const y = data.at?.[1] ?? 0;
            const width = data.size?.[0] ?? 0;
            const height = data.size?.[1] ?? 0;
            return globalX >= x && globalX < x + width
                && globalY >= y && globalY < y + height;
        }).sort((a, b) => {
            // Match the compositor's useful stacking classes: pinned above
            // normal, then fullscreen, then floating, then tiled windows.
            const ac = a.lastIpcObject;
            const bc = b.lastIpcObject;
            return (bc.pinned - ac.pinned)
                || ((bc.fullscreen !== 0) - (ac.fullscreen !== 0))
                || (bc.floating - ac.floating);
        });

        const hovered = candidates[0];
        if (hovered && hovered.address !== windowInfoClient?.address)
            windowInfoClient = hovered;
    }

    // Never leave sticky latched after a hover closes (search used to do this).
    onHasCurrentChanged: {
        if (!hasCurrent)
            sticky = false;
    }

    // Dummy object so Tokens attached prop resolves to global config
    // Anim configs are not per-monitor
    readonly property QtObject dummy: QtObject {}
    property int animLength: dummy.Tokens.anim.durations.expressiveDefaultSpatial
    property var animCurve: dummy.Tokens.anim.expressiveDefaultSpatial // The easingCurve type is Qt 6.11+ so we gotta use var for now

    function setAnims(detach: bool): void {
        const type = `expressive${detach ? "Slow" : "Default"}Spatial`;
        animLength = dummy.Tokens.anim.durations[type];
        animCurve = dummy.Tokens.anim[type];
    }

    function detach(mode: string): void {
        setAnims(true);
        sticky = false;
        hasCurrent = false;
        if (mode === "winfo") {
            windowInfoClient = Hypr.activeToplevel;
            detachedMode = mode;
        } else if (mode === "clipboard") {
            detachedMode = "clipboard";
        } else if (mode === "link") {
            detachedMode = "link";
        } else if (mode === "calendar") {
            detachedMode = "calendar";
        } else {
            queuedMode = mode;
            detachedMode = "any";
        }
        setAnims(false);
        focus = true;
    }

    function openSticky(name: string, center: real): void {
        detachedMode = "";
        currentName = name;
        currentCenter = center;
        sticky = true;
        hasCurrent = true;
        focus = true;
    }

    function close(): void {
        hasCurrent = false;
        sticky = false;
        detachedMode = "";
        // Ensure layer-shell keyboard is released with the panel.
        focus = false;
    }

    implicitWidth: nonAnimWidth
    implicitHeight: nonAnimHeight

    focus: hasCurrent || isDetached
    Keys.onEscapePressed: {
        // Forward escape to password popout if active, otherwise close
        if (currentName === "wirelesspassword" && content.item) {
            const passwordPopout = (content.item as Content)?.children.find(c => c.name === "wirelesspassword");
            if (passwordPopout && passwordPopout.item) {
                passwordPopout.item.closeDialog();
                return;
            }
        }
        close();
    }

    // Popouts that own a text field and must receive keys (not the focused client).
    readonly property bool needsKeyboard: (root.isDetached && root.detachedMode !== "winfo")
        || (root.hasCurrent && (root.currentName === "wirelesspassword"
            || root.currentName === "clipboardhover"))

    Keys.onPressed: event => {
        // Don't intercept keys when a nested text field owns them.
        if (currentName === "wirelesspassword" || currentName === "clipboardhover") {
            event.accepted = false;
        }
    }

    PopoutState {
        id: popoutState

        onDetachRequested: mode => root.detach(mode)
    }

    // Only grab focus for detached panels (settings/clipboard), and only after a
    // short delay so open-from-click/IPC is not immediately cancelled by onCleared.
    Timer {
        id: focusGrabDelay
        interval: 180
        onTriggered: root.focusGrabReady = root.isDetached
    }
    property bool focusGrabReady: false
    onIsDetachedChanged: {
        if (isDetached && detachedMode !== "winfo") {
            focusGrabReady = false;
            focusGrabDelay.restart();
        } else {
            focusGrabDelay.stop();
            focusGrabReady = false;
        }
    }

    HyprlandFocusGrab {
        // Clipboard owns a persistent search field. Settings and Caelestia
        // Link use the full-screen scrim for click-outside dismissal instead;
        // grabbing compositor focus there made focus-follows-mouse close them
        // merely because the pointer crossed onto the underlying window.
        active: root.focusGrabReady && root.detachedMode === "clipboard"
        windows: [QsWindow.window]
        onCleared: root.close()
    }

    Binding {
        // OnDemand so TextInputs (password, clipboard search) can take keys.
        // Without this, layer-shell has keyboardFocus None and keys pass through
        // to the focused app behind the hover panel.
        when: root.needsKeyboard

        target: QsWindow.window
        property: "WlrLayershell.keyboardFocus"
        value: WlrKeyboardFocus.OnDemand
    }

    Comp {
        id: content

        shouldBeActive: root.hasCurrent && !root.detachedMode
        anchors.fill: parent

        sourceComponent: Content {
            popouts: popoutState
        }
    }

    Comp {
        id: winfo

        shouldBeActive: root.detachedMode === "winfo"
        anchors.centerIn: parent

        sourceComponent: WindowInfo {
            screen: root.screen
            client: root.windowInfoClient
        }
    }

    Comp {
        id: nexus

        shouldBeActive: root.detachedMode === "any"
        anchors.centerIn: parent

        sourceComponent: StyledClippingRect {
            radius: Tokens.rounding.extraLarge
            implicitWidth: nexusInner.implicitWidth
            implicitHeight: nexusInner.implicitHeight

            Nexus {
                id: nexusInner

                anchors.fill: parent
                nState.screen: root.screen
                nState.currentPageIdx: ["appearance", "display", "network", "bluetooth", "audio", "power"].indexOf(root.queuedMode)
                onClose: root.close()
            }
        }
    }

    Comp {
        id: clipboard

        shouldBeActive: root.detachedMode === "clipboard"
        anchors.centerIn: parent
        // Ensure the loader reports a real size while the panel is open
        width: item ? item.implicitWidth : 0
        height: item ? item.implicitHeight : 0

        sourceComponent: Clipboard {
            onClosed: root.close()
        }
    }

    Comp {
        id: link

        shouldBeActive: root.detachedMode === "link"
        anchors.centerIn: parent

        sourceComponent: ContinuityModule.LinkSettings {
            initialPage: root.linkPage
            onCloseRequested: root.close()
        }
    }

    Comp {
        id: calendar

        shouldBeActive: root.detachedMode === "calendar"
        anchors.centerIn: parent

        sourceComponent: CalendarModule.CalendarCentreView {
            initialPage: root.calendarPage
            onCloseRequested: root.close()
        }
    }

    Behavior on implicitWidth {
        Anim {
            duration: root.animLength
            easing: root.animCurve
        }
    }

    Behavior on implicitHeight {
        enabled: root.offsetScale < 1

        Anim {
            duration: root.animLength
            easing: root.animCurve
        }
    }

    component Comp: Loader {
        id: comp

        property bool shouldBeActive

        active: false
        opacity: 0

        // Makes the loader load on the same frame shouldBeActive becomes true, which ensures size is set
        states: State {
            name: "active"
            when: comp.shouldBeActive

            PropertyChanges {
                comp.opacity: 1
                comp.active: true
            }
        }

        transitions: [
            Transition {
                from: ""
                to: "active"

                SequentialAnimation {
                    PropertyAction {
                        property: "active"
                    }
                    Anim {
                        type: Anim.DefaultEffects
                        property: "opacity"
                    }
                }
            },
            Transition {
                from: "active"
                to: ""

                SequentialAnimation {
                    Anim {
                        type: Anim.DefaultEffects
                        property: "opacity"
                    }
                    PropertyAction {
                        property: "active"
                    }
                }
            }
        ]
    }
}
