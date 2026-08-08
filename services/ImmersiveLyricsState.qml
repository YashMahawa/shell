pragma Singleton

import QtQml
import Quickshell

Singleton {
    id: root

    property bool active: false
    property bool closing: false
    property string screenName: ""
    readonly property bool presented: active && !closing

    function open(targetScreen: string): void {
        screenName = targetScreen || "";
        closing = false;
        active = true;
    }

    function close(): void {
        if (!active)
            return;
        closing = true;
    }

    function toggle(targetScreen: string): void {
        if (active)
            close();
        else
            open(targetScreen);
    }

    Timer {
        id: closeDelay

        interval: 460
        repeat: false
        running: root.closing
        onTriggered: {
            root.active = false;
            root.closing = false;
        }
    }
}
