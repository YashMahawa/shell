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
        closeDelay.stop();
        screenName = targetScreen || "";
        closing = false;
        active = true;
    }

    function close(): void {
        if (!active || closing)
            return;
        closing = true;
        closeDelay.restart();
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
        onTriggered: {
            root.active = false;
            root.closing = false;
        }
    }
}
