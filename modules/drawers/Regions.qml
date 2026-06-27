pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.modules.bar as Bar

Region {
    id: root

    required property Bar.BarWrapper bar
    required property Panels panels
    required property var win

    readonly property real borderThickness: win.contentItem.Config.border.thickness
    readonly property real clampedThickness: win.contentItem.Config.border.clampedThickness
    readonly property real edgeThickness: Math.max(win.contentItem.Config.border.minThickness ?? 0, win.contentItem.Config.border.thickness ?? 0, 8)
    readonly property real barWidth: Math.max(root.bar?.implicitWidth ?? 0, root.bar?.clampedThickness ?? 0, edgeThickness)
    readonly property bool needsClickAwaySurface: root.panels.popouts.isDetached

    Region {
        x: 0
        y: 0
        width: root.needsClickAwaySurface ? root.win.width : root.barWidth
        height: root.win.height
    }

    Region {
        x: root.barWidth
        y: 0
        width: root.win.width - root.barWidth
        height: root.edgeThickness
    }

    Region {
        x: root.barWidth
        y: root.win.height - root.edgeThickness
        width: root.win.width - root.barWidth
        height: root.edgeThickness
    }

    Region {
        x: root.win.width - width
        y: 0
        width: root.edgeThickness
        height: root.win.height
    }

    R {
        panel: root.panels.dashboard
        y: 0
        height: Math.max(root.edgeThickness, panel.height * (1 - root.panels.dashboard.offsetScale) + root.borderThickness)
    }

    R {
        panel: root.panels.launcher
        y: root.win.height - height
        height: Math.max(root.edgeThickness, panel.height * (1 - root.panels.launcher.offsetScale) + root.borderThickness)
    }

    R {
        panel: root.panels.utilities
        y: root.win.height - height
        height: Math.max(root.edgeThickness, panel.height * (1 - root.panels.utilities.offsetScale) + root.borderThickness)
    }

    R {
        panel: root.panels.popoutsWrapper
        width: panel.width * (1 - root.panels.popoutsWrapper.offsetScale)
    }

    R {
        panel: root.panels.osdWrapper
        width: panel.width
    }

    R {
        panel: root.panels.notifications
    }

    component R: Region {
        required property Item panel

        x: panel.x + root.bar.implicitWidth
        y: panel.y + root.borderThickness
        width: panel.width
        height: panel.height
    }
}
