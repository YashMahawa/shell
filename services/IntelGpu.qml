pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config

Singleton {
    id: root

    readonly property string name: "Intel iGPU"
    property real percentage: 0
    property bool available: false
    property int refCount: 0

    function refresh(): void {
        activeFreq.reload();
        minimumFreq.reload();
        maximumFreq.reload();
    }

    function updatePercentage(): void {
        const current = Number(activeFreq.text().trim());
        const minimum = Number(minimumFreq.text().trim());
        const maximum = Number(maximumFreq.text().trim());

        root.available = Number.isFinite(current) && Number.isFinite(minimum) && Number.isFinite(maximum) && maximum > minimum;
        if (!root.available) {
            root.percentage = 0;
            return;
        }

        // Caelestia performance services use a normalized 0.0–1.0 value.
        root.percentage = Math.max(0, Math.min(1, (current - minimum) / (maximum - minimum)));
    }

    Timer {
        interval: GlobalConfig.dashboard.resourceUpdateInterval
        running: root.refCount > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    FileView {
        id: activeFreq

        path: "/sys/devices/pci0000:00/0000:00:02.0/drm/card1/gt_act_freq_mhz"
        printErrors: false
        onLoaded: root.updatePercentage()
    }

    FileView {
        id: minimumFreq

        path: "/sys/devices/pci0000:00/0000:00:02.0/drm/card1/gt_RPn_freq_mhz"
        printErrors: false
        onLoaded: root.updatePercentage()
    }

    FileView {
        id: maximumFreq

        path: "/sys/devices/pci0000:00/0000:00:02.0/drm/card1/gt_RP0_freq_mhz"
        printErrors: false
        onLoaded: root.updatePercentage()
    }
}
