pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

Singleton {
    id: root

    property bool active: false
    property string status: "off"

    function stopDiscovery(): void {
        const adapter = Bluetooth.defaultAdapter; // qmllint disable unresolved-type
        if (adapter?.discovering)
            adapter.discovering = false;
    }

    onActiveChanged: {
        if (active)
            stopDiscovery();
    }

    Component.onCompleted: {
        if (active)
            stopDiscovery();
    }

    function toggle(): void {
        Quickshell.execDetached(["/home/yash/.local/bin/caelestia-ultra-power", "toggle"]);
    }

    function selectProfile(profile: string): void {
        if (active)
            Quickshell.execDetached(["/home/yash/.local/bin/caelestia-ultra-power", "off", profile]);
        else
            Quickshell.execDetached(["powerprofilesctl", "set", profile]);
    }

    FileView {
        path: "/home/yash/.local/state/caelestia/ultra-power.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const state = JSON.parse(text());
                root.active = state.active ?? false;
                root.status = state.status ?? "off";
            } catch (error) {
                root.active = false;
                root.status = "off";
            }
        }
    }
}
