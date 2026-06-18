pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string name: "Intel iGPU"
    property int percentage: 0
    property bool available: false

    function refresh(): void {
        sampler.running = true;
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: sampler

        command: ["sh", "-c", "base=/sys/devices/pci0000:00/0000:00:02.0/drm/card1; [ -r \"$base/gt_act_freq_mhz\" ] || base=/sys/class/drm/card1; cur=$(cat \"$base/gt_act_freq_mhz\" 2>/dev/null || cat \"$base/gt_cur_freq_mhz\" 2>/dev/null || echo 0); min=$(cat \"$base/gt_RPn_freq_mhz\" 2>/dev/null || echo 0); max=$(cat \"$base/gt_RP0_freq_mhz\" 2>/dev/null || cat \"$base/gt_max_freq_mhz\" 2>/dev/null || echo 0); awk -v c=\"$cur\" -v n=\"$min\" -v x=\"$max\" 'BEGIN { if (x <= n || c <= 0) print \"0 0\"; else { p=(c-n)*100/(x-n); if (p<0) p=0; if (p>100) p=100; printf \"1 %.0f\\n\", p } }'"]
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split(/\s+/);
                root.available = parts[0] === "1";
                root.percentage = root.available ? Number(parts[1] ?? 0) : 0;
            }
        }
    }
}
