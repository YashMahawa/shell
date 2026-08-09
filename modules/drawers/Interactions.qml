import QtQuick
import QtQuick.Controls
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.bar as Bar
import qs.modules.bar.popouts as BarPopouts

CustomMouseArea {
    id: root

    required property ShellScreen screen
    required property BarPopouts.Wrapper popouts
    required property DrawerVisibilities visibilities
    required property Panels panels
    required property Bar.BarWrapper bar
    required property real borderThickness
    required property bool fullscreen
    required property bool dashboardHoverBlocked

    property point dragStart
    property bool dashboardShortcutActive
    property bool osdShortcutActive
    property bool utilitiesShortcutActive
    property bool sidebarHoverActive
    readonly property real barTriggerWidth: Math.max(bar?.implicitWidth ?? 0, bar?.clampedThickness ?? 0, Config.border.minThickness ?? 0, Config.border.thickness ?? 0, 8)
    readonly property real topRightHotCornerSize: Math.max(24, Config.border.rounding, Config.border.thickness * 2)

    onDashboardHoverBlockedChanged: {
        if (dashboardHoverBlocked) {
            dashboardShortcutActive = false;
            visibilities.dashboard = false;
        }
    }

    function withinPanelHeight(panel: Item, x: real, y: real): bool {
        const panelHeight = panel.height || panel.implicitHeight;
        const panelY = root.borderThickness + panel.y;
        return y >= panelY - Config.border.rounding && y <= panelY + panelHeight + Config.border.rounding;
    }

    function withinPanelWidth(panel: Item, x: real, y: real): bool {
        const panelWidth = panel.width || panel.implicitWidth;
        const panelX = bar.implicitWidth + (panel.width ? panel.x : (panel.x - panel.implicitWidth / 2));
        return x >= panelX - Config.border.rounding && x <= panelX + panelWidth + Config.border.rounding;
    }

    function inLeftPanel(panel: Item, x: real, y: real): bool {
        const panelWidth = panel.width || panel.implicitWidth;
        return x < bar.implicitWidth + panel.x + panelWidth && withinPanelHeight(panel, x, y);
    }

    readonly property bool hoverSidePopout: popouts.hasCurrent
        && (popouts.currentName === "continuity" || popouts.currentName === "clipboardhover")

    function overPopoutsPanel(x: real, y: real): bool {
        const panel = panels.popoutsWrapper;
        if (!panel || !popouts.hasCurrent)
            return false;
        // Map into the popout item — more reliable than hand-rolled geometry
        // (panels margins / deform / animation make absolute math flaky).
        const p = panel.mapFromItem(root, x, y);
        const pad = 28;
        return p.x >= -pad && p.y >= -pad
            && p.x <= Math.max(panel.width, panel.implicitWidth) + pad
            && p.y <= Math.max(panel.height, panel.implicitHeight) + pad;
    }

    function overDetachedContent(x: real, y: real): bool {
        if (!popouts.isDetached)
            return false;
        const point = popouts.mapFromItem(root, x, y);
        return point.x >= 0 && point.y >= 0
            && point.x <= popouts.width && point.y <= popouts.height;
    }

    function overPanel(panel: Item, x: real, y: real, padding = 16): bool {
        if (!panel)
            return false;
        const point = panel.mapFromItem(root, x, y);
        const panelWidth = Math.max(panel.width, panel.implicitWidth, 0);
        const panelHeight = Math.max(panel.height, panel.implicitHeight, 0);
        return point.x >= -padding && point.y >= -padding
            && point.x <= panelWidth + padding
            && point.y <= panelHeight + padding;
    }

    function updateSidebarAutoHide(x: real, y: real): void {
        if (!sidebarHoverActive || !visibilities.sidebar) {
            sidebarHideTimer.stop();
            return;
        }
        const overHotCorner = x >= width - topRightHotCornerSize
            && y <= topRightHotCornerSize;
        const overOverlay = overSidebarPanel(x, y) || overHotCorner;
        if (overOverlay)
            sidebarHideTimer.stop();
        else if (!sidebarHideTimer.running)
            sidebarHideTimer.restart();
    }

    function overSidebarPanel(x: real, y: real): bool {
        const panelWidth = Math.max(panels.sidebar.width, panels.sidebar.implicitWidth, 0);
        const visibleWidth = panelWidth * (1 - (panels.sidebar.offsetScale ?? 0));
        return visibleWidth > 1 && x >= width - visibleWidth - 20;
    }

    function overContinuityHoverPopout(x: real, y: real): bool {
        if (!hoverSidePopout)
            return false;
        if (x < bar.implicitWidth)
            return true; // still on the bar strip
        if (overPopoutsPanel(x, y))
            return true;
        // Bridge between bar edge and panel.
        const bridge = Math.max(120, Config.border.rounding * 4);
        return x < bar.implicitWidth + bridge;
    }

    function inPanelBounds(panel: Item, x: real, y: real): bool {
        const panelWidth = panel.width || panel.implicitWidth;
        const panelHeight = panel.height || panel.implicitHeight;
        const panelX = bar.implicitWidth + (panel.width ? panel.x : (panel.x - panel.implicitWidth));
        const panelY = root.borderThickness + panel.y;
        return x >= panelX - Config.border.rounding && x <= panelX + panelWidth + Config.border.rounding && y >= panelY - Config.border.rounding && y <= panelY + panelHeight + Config.border.rounding;
    }

    function inRightPanel(panel: Item, x: real, y: real): bool {
        const panelWidth = panel.width || panel.implicitWidth;
        const panelX = panel.width ? panel.x : (panel.x - panel.implicitWidth);
        // Animated right panels collapse their width to zero while hidden.
        // Keep a comfortable edge target so the OSD can still be discovered
        // reliably on large external monitors.
        const edgeTrigger = width - Math.max(32, Config.border.minThickness, Config.border.thickness * 2);
        return x > Math.min(edgeTrigger, bar.implicitWidth + panelX) && withinPanelHeight(panel, x, y);
    }

    function inTopPanel(panel: Item, x: real, y: real): bool {
        const panelHeight = (panel.height || panel.implicitHeight) * (1 - (panel.offsetScale ?? 0)); // qmllint disable missing-property
        return y < Math.max(Config.border.minThickness, Config.border.thickness + panelHeight) && withinPanelWidth(panel, x, y);
    }

    function inBottomPanel(panel: Item, x: real, y: real, isCorner = false): bool {
        const panelHeight = (panel.height || panel.implicitHeight) * (1 - (panel.offsetScale ?? 0)); // qmllint disable missing-property
        return y > height - Math.max(Config.border.minThickness, Config.border.thickness + panelHeight) - (isCorner ? Config.border.rounding : 0) && withinPanelWidth(panel, x, y);
    }

    function onWheel(event: WheelEvent): void {
        if (fullscreen)
            return;
        if (event.x < bar.implicitWidth) {
            bar.handleWheel(event.x, event.y, event.angleDelta);
        }
    }

    anchors.fill: parent
    acceptedButtons: popouts.isDetached ? Qt.LeftButton : Qt.NoButton
    hoverEnabled: true

    onPressed: event => dragStart = Qt.point(event.x, event.y)
    onClicked: event => {
        // Center detach panels (clipboard / settings): click outside to close.
        if (popouts.isDetached && !overDetachedContent(event.x, event.y))
            popouts.close();
    }


    // Dedicated click-away surface below the panels but above applications.
    // The parent CustomMouseArea did not receive composed clicks consistently
    // when a child panel or its full-screen item tree owned the pointer grab.
    MouseArea {
        anchors.fill: parent
        enabled: root.popouts.detachedMode === "any"
            || root.popouts.detachedMode === "link"
            || root.popouts.detachedMode === "calendar"
        acceptedButtons: Qt.LeftButton
        onClicked: event => {
            if (!root.overDetachedContent(event.x, event.y))
                root.popouts.close();
        }
    }
    onContainsMouseChanged: {
        if (containsMouse) {
            updateSidebarAutoHide(mouseX, mouseY);
            return;
        }
        if (!containsMouse) {
            if (!osdShortcutActive) {
                visibilities.osd = false;
                root.panels.osd.hovered = false;
            }

            if (!dashboardShortcutActive)
                visibilities.dashboard = false;

            if (!utilitiesShortcutActive && !root.panels.utilities.interactionPinned)
                visibilities.utilities = false;

            if (sidebarHoverActive)
                sidebarHideTimer.restart();

            // Same as wifi/bluetooth: leaving the shell surface closes hover popouts.
            if (!popouts.isDetached) {
                if (!popouts.currentName.startsWith("traymenu") || ((popouts.current as StackView)?.depth ?? 0) <= 1) {
                    popouts.sticky = false;
                    popouts.hasCurrent = false;
                    bar.closeTray();
                }
            }

            if (Config.bar.showOnHover)
                bar.isHovered = false;
        }
    }

    Timer {
        id: sidebarHideTimer

        interval: 180
        onTriggered: {
            const stillOverOverlay = root.containsMouse
                && (root.overSidebarPanel(root.mouseX, root.mouseY)
                    || (root.mouseX >= root.width - root.topRightHotCornerSize
                        && root.mouseY <= root.topRightHotCornerSize));
            if (!stillOverOverlay && root.sidebarHoverActive) {
                root.visibilities.sidebar = false;
                root.sidebarHoverActive = false;
            }
        }
    }

    Timer {
        id: hoverPopoutHideTimer
        interval: 220
        onTriggered: {
            if (root.popouts.isDetached)
                return;
            // Keep open while still over bar or the side panel (wifi-style).
            if (root.containsMouse) {
                if (root.mouseX < root.bar.implicitWidth)
                    return;
                if (root.overPopoutsPanel(root.mouseX, root.mouseY)
                    || root.inLeftPanel(root.panels.popoutsWrapper, root.mouseX, root.mouseY))
                    return;
            }
            if (!root.popouts.currentName.startsWith("traymenu") || ((root.popouts.current as StackView)?.depth ?? 0) <= 1) {
                root.popouts.sticky = false;
                root.popouts.hasCurrent = false;
                root.bar.closeTray();
            }
        }
    }

    onPositionChanged: event => {
        const x = event.x;
        const y = event.y;
        updateSidebarAutoHide(x, y);

        if (popouts.isDetached) {
            // The detached window-info surface sits above applications, so
            // Hyprland cannot focus the underlying client directly.  Resolve
            // it from the pointer and client rectangles instead.  Do not
            // change selection while the pointer is over the controls.
            if (popouts.detachedMode === "winfo"
                && !overPopoutsPanel(event.x, event.y))
                popouts.selectWindowInfoClientAt(screen.x + event.x, screen.y + event.y);
            return;
        }

        const dragX = x - dragStart.x;
        const dragY = y - dragStart.y;

        if (fullscreen) {
            const showOsd = inRightPanel(panels.osdWrapper, x, y);
            if (!osdShortcutActive) {
                visibilities.osd = showOsd;
                root.panels.osd.hovered = showOsd;
            } else if (showOsd) {
                osdShortcutActive = false;
                root.panels.osd.hovered = true;
            }
            return;
        }

        // A deliberate trip to the top-right corner opens the notification
        // centre and leaves it open for interaction until normal click-away.
        if (!visibilities.sidebar && x >= width - topRightHotCornerSize && y <= topRightHotCornerSize) {
            visibilities.session = false;
            visibilities.utilities = false;
            visibilities.sidebar = true;
            sidebarHoverActive = true;
        }

        // Show bar in non-exclusive mode on hover
        if (!visibilities.bar && Config.bar.showOnHover && x < barTriggerWidth)
            bar.isHovered = true;

        // Show/hide bar on drag
        if (pressed && dragStart.x < barTriggerWidth) {
            if (dragX > Config.bar.dragThreshold)
                visibilities.bar = true;
            else if (dragX < -Config.bar.dragThreshold)
                visibilities.bar = false;
        }

        if (panels.sidebar.offsetScale === 1) {
            // Show osd on hover
            const showOsd = inRightPanel(panels.osdWrapper, x, y);

            // Always update visibility based on hover if not in shortcut mode
            if (!osdShortcutActive) {
                visibilities.osd = showOsd;
                root.panels.osd.hovered = showOsd;
            } else if (showOsd) {
                // If hovering over OSD area while in shortcut mode, transition to hover control
                osdShortcutActive = false;
                root.panels.osd.hovered = true;
            }

            const showSidebar = pressed && dragStart.x > Math.min(width - Config.border.minThickness, bar.implicitWidth + panels.sidebar.x);

            // Show/hide session on drag
            if (pressed && inRightPanel(panels.sessionWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.sessionWrapper, x, y)) {
                if (dragX < -Config.session.dragThreshold)
                    visibilities.session = true;
                else if (dragX > Config.session.dragThreshold)
                    visibilities.session = false;

                // Show sidebar on drag if in session area and session is nearly fully visible
                if (showSidebar && panels.session.offsetScale <= 0 && dragX < -Config.sidebar.dragThreshold)
                    visibilities.sidebar = true;
            } else if (showSidebar && dragX < -Config.sidebar.dragThreshold) {
                // Show sidebar on drag if not in session area
                visibilities.sidebar = true;
            }
        } else {
            const outOfSidebar = x < width - panels.sidebar.width * (1 - panels.sidebar.offsetScale);
            // Show osd on hover
            const showOsd = outOfSidebar && inRightPanel(panels.osdWrapper, x, y);

            // Always update visibility based on hover if not in shortcut mode
            if (!osdShortcutActive) {
                visibilities.osd = showOsd;
                root.panels.osd.hovered = showOsd;
            } else if (showOsd) {
                // If hovering over OSD area while in shortcut mode, transition to hover control
                osdShortcutActive = false;
                root.panels.osd.hovered = true;
            }

            // Show/hide session on drag
            if (pressed && outOfSidebar && inRightPanel(panels.sessionWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.sessionWrapper, x, y)) {
                if (dragX < -Config.session.dragThreshold)
                    visibilities.session = true;
                else if (dragX > Config.session.dragThreshold)
                    visibilities.session = false;
            }

            // Hide sidebar on drag
            if (pressed && inRightPanel(panels.sidebar, dragStart.x, 0) && dragX > Config.sidebar.dragThreshold)
                visibilities.sidebar = false;
        }

        // Show launcher on hover, or show/hide on drag if hover is disabled
        if (Config.launcher.showOnHover) {
            if (!visibilities.launcher && inBottomPanel(panels.launcher, x, y))
                visibilities.launcher = true;
        } else if (pressed && inBottomPanel(panels.launcher, dragStart.x, dragStart.y) && withinPanelWidth(panels.launcher, x, y)) {
            if (dragY < -Config.launcher.dragThreshold)
                visibilities.launcher = true;
            else if (dragY > Config.launcher.dragThreshold)
                visibilities.launcher = false;
        }

        // Show dashboard on hover
        const showDashboard = !dashboardHoverBlocked && Config.dashboard.showOnHover && inTopPanel(panels.dashboard, x, y);

        // Always update visibility based on hover if not in shortcut mode
        if (!dashboardShortcutActive) {
            visibilities.dashboard = showDashboard;
        } else if (showDashboard) {
            // If hovering over dashboard area while in shortcut mode, transition to hover control
            dashboardShortcutActive = false;
        }

        // Show/hide dashboard on drag (for touchscreen devices)
        if (!dashboardHoverBlocked && pressed && inTopPanel(panels.dashboard, dragStart.x, dragStart.y) && withinPanelWidth(panels.dashboard, x, y)) {
            if (dragY > Config.dashboard.dragThreshold)
                visibilities.dashboard = true;
            else if (dragY < -Config.dashboard.dragThreshold)
                visibilities.dashboard = false;
        }

        // Show utilities on hover
        const showUtilities = !visibilities.sidebar && !sidebarHoverActive && inBottomPanel(panels.utilities, x, y, true);

        // Always update visibility based on hover if not in shortcut mode
        if (panels.utilities.interactionPinned) {
            visibilities.utilities = true;
        } else if (!utilitiesShortcutActive) {
            visibilities.utilities = showUtilities;
        } else if (showUtilities) {
            // If hovering over utilities area while in shortcut mode, transition to hover control
            utilitiesShortcutActive = false;
        }

        // Hover popouts (wifi, bluetooth, Link, clipboard…): identical rules.
        if (popouts.isDetached)
            return;

        if (x < bar.implicitWidth) {
            hoverPopoutHideTimer.stop();
            bar.checkPopout(x, y);
        } else if (overPopoutsPanel(x, y) || inLeftPanel(panels.popoutsWrapper, x, y)) {
            // Pointer made it onto the side panel — keep it open.
            hoverPopoutHideTimer.stop();
        } else if ((!popouts.currentName.startsWith("traymenu") || ((popouts.current as StackView)?.depth ?? 0) <= 1)) {
            if (popouts.hasCurrent)
                hoverPopoutHideTimer.restart();
        }
    }

    // Monitor individual visibility changes
    Connections {
        function onLauncherChanged() {
            // If launcher is hidden, clear shortcut flags for dashboard and OSD
            if (!root.visibilities.launcher) {
                root.dashboardShortcutActive = false;
                root.osdShortcutActive = false;
                root.utilitiesShortcutActive = false;

                // Also hide dashboard and OSD if they're not being hovered
                const inDashboardArea = root.inTopPanel(root.panels.dashboard, root.mouseX, root.mouseY);
                const inOsdArea = root.inRightPanel(root.panels.osdWrapper, root.mouseX, root.mouseY);

                if (!inDashboardArea) {
                    root.visibilities.dashboard = false;
                }
                if (!inOsdArea) {
                    root.visibilities.osd = false;
                    root.panels.osd.hovered = false;
                }
            }
        }

        function onDashboardChanged() {
            if (root.visibilities.dashboard) {
                // Dashboard became visible, immediately check if this should be shortcut mode
                const inDashboardArea = root.inTopPanel(root.panels.dashboard, root.mouseX, root.mouseY);
                if (!inDashboardArea) {
                    root.dashboardShortcutActive = true;
                }
            } else {
                // Dashboard hidden, clear shortcut flag
                root.dashboardShortcutActive = false;
            }
        }

        function onOsdChanged() {
            if (root.visibilities.osd) {
                // OSD became visible, immediately check if this should be shortcut mode
                const inOsdArea = root.inRightPanel(root.panels.osdWrapper, root.mouseX, root.mouseY);
                if (!inOsdArea) {
                    root.osdShortcutActive = true;
                }
            } else {
                // OSD hidden, clear shortcut flag
                root.osdShortcutActive = false;
            }
        }

        function onUtilitiesChanged() {
            if (root.visibilities.utilities) {
                // Utilities became visible, immediately check if this should be shortcut mode
                const inUtilitiesArea = root.inBottomPanel(root.panels.utilities, root.mouseX, root.mouseY);
                if (!inUtilitiesArea) {
                    root.utilitiesShortcutActive = true;
                }
            } else {
                // Utilities hidden, clear shortcut flag
                root.utilitiesShortcutActive = false;
            }
        }

        target: root.visibilities
    }
}
