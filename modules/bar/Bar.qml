pragma ComponentBehavior: Bound

import "popouts" as BarPopouts
import "components"
import "components/workspaces"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

GridLayout {
    id: root

    required property ShellScreen screen
    required property DrawerVisibilities visibilities
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen
    readonly property int vPadding: Tokens.padding.large
    readonly property bool isVertical: Config.bar.edge === "left" || Config.bar.edge === "right"
    flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight

    function closeTray(): void {
        if (!Config.bar.tray.compact)
            return;

        for (let i = 0; i < repeater.count; i++) {
            const loader = repeater.itemAt(i) as WrappedLoader;
            if (loader?.enabled && loader.id === "tray") {
                (loader.item as Tray).expanded = false;
            }
        }
    }

    function checkPopout(x: real, y: real): void {
        const primary = isVertical ? y : x;
        const cross = isVertical ? width / 2 : height / 2;
        const ch = childAt(isVertical ? cross : primary, isVertical ? primary : cross) as WrappedLoader;

        if (ch?.id !== "tray")
            closeTray();

        if (!ch) {
            popouts.hasCurrent = false;
            return;
        }

        const id = ch.id;
        const top = isVertical ? ch.y : ch.x;

        if (id === "statusIcons" && Config.bar.popouts.statusIcons) {
            const items = (ch.item as StatusIcons).items;
            const mapped = mapToItem(items, x, y);
            const icon = items.childAt(isVertical ? items.width / 2 : mapped.x, isVertical ? mapped.y : items.height / 2);
            if (icon) {
                popouts.currentName = icon.name;
                popouts.currentCenter = Qt.binding(() => icon.mapToItem(root, isVertical ? 0 : icon.implicitWidth / 2, isVertical ? icon.implicitHeight / 2 : 0)[isVertical ? 'y' : 'x']);
                popouts.hasCurrent = true;
            }
        } else if (id === "tray" && Config.bar.popouts.tray) {
            const tray = ch.item as Tray;
            if (!Config.bar.tray.compact || (tray.expanded && !tray.expandIcon.contains(mapToItem(tray.expandIcon, x, y)))) {
                const index = Math.floor(((primary - top - tray.padding * 2 + tray.spacing) / (isVertical ? tray.layout.implicitHeight : tray.layout.implicitWidth)) * tray.items.count);
                const trayItem = tray.items.itemAt(index);
                if (trayItem) {
                    popouts.currentName = `traymenu${index}`;
                    popouts.currentCenter = Qt.binding(() => trayItem.mapToItem(root, isVertical ? 0 : trayItem.implicitWidth / 2, isVertical ? trayItem.implicitHeight / 2 : 0)[isVertical ? 'y' : 'x']);
                    popouts.hasCurrent = true;
                } else {
                    popouts.hasCurrent = false;
                }
            } else {
                popouts.hasCurrent = false;
                tray.expanded = true;
            }
        } else if (id === "activeWindow" && Config.bar.popouts.activeWindow && Config.bar.activeWindow.showOnHover) {
            popouts.currentName = id.toLowerCase();
            const mappedItem = (ch.item as Item).mapToItem(root, isVertical ? 0 : (ch.item as Item).implicitWidth / 2, isVertical ? (ch.item as Item).implicitHeight / 2 : 0);
            popouts.currentCenter = mappedItem[isVertical ? 'y' : 'x'] ?? 0;
            popouts.hasCurrent = true;
        }
    }

    function handleWheel(x: real, y: real, angleDelta: point): void {
        const primary = isVertical ? y : x;
        const cross = isVertical ? width / 2 : height / 2;
        const ch = childAt(isVertical ? cross : primary, isVertical ? primary : cross) as WrappedLoader;
        const mainSize = isVertical ? screen.height : screen.width;

        if (ch?.id === "workspaces" && Config.bar.scrollActions.workspaces) {
            // Workspace scroll
            const mon = (GlobalConfig.bar.workspaces.perMonitorWorkspaces ? Hypr.monitorFor(screen) : Hypr.focusedMonitor);
            const specialWs = mon?.lastIpcObject.specialWorkspace.name;
            if (specialWs?.length > 0)
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.workspace.toggle_special("${specialWs.slice(8)}")` : `togglespecialworkspace ${specialWs.slice(8)}`);
            else if (angleDelta.y < 0 || (GlobalConfig.bar.workspaces.perMonitorWorkspaces ? mon.activeWorkspace?.id : Hypr.activeWsId) > 1)
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = "r${angleDelta.y > 0 ? "-" : "+"}1" })` : `workspace r${angleDelta.y > 0 ? "-" : "+"}1`);
        } else if (primary < mainSize / 2 && Config.bar.scrollActions.volume) {
            // Volume scroll on top half
            if (angleDelta.y > 0)
                Audio.incrementVolume();
            else if (angleDelta.y < 0)
                Audio.decrementVolume();
        } else if (Config.bar.scrollActions.brightness) {
            // Brightness scroll on bottom half
            const monitor = Brightness.getMonitorForScreen(screen);
            if (angleDelta.y > 0)
                monitor.setBrightness(monitor.brightness + GlobalConfig.services.brightnessIncrement);
            else if (angleDelta.y < 0)
                monitor.setBrightness(monitor.brightness - GlobalConfig.services.brightnessIncrement);
        }
    }

    rowSpacing: Tokens.spacing.medium
    columnSpacing: Tokens.spacing.medium

    Repeater {
        id: repeater

        model: Config.bar.entries

        DelegateChooser {
            role: "id"

            DelegateChoice {
                roleValue: "spacer"
                delegate: WrappedLoader {
                    Layout.fillHeight: enabled
                }
            }
            DelegateChoice {
                roleValue: "logo"
                delegate: WrappedLoader {
                    sourceComponent: OsIcon {}
                }
            }
            DelegateChoice {
                roleValue: "workspaces"
                delegate: WrappedLoader {
                    sourceComponent: Workspaces {
                        screen: root.screen
                        fullscreen: root.fullscreen
                    }
                }
            }
            DelegateChoice {
                roleValue: "activeWindow"
                delegate: WrappedLoader {
                    Layout.fillWidth: true
                    visible: !root.fullscreen
                    sourceComponent: ActiveWindow {
                        bar: root
                        monitor: Brightness.getMonitorForScreen(root.screen)
                    }
                }
            }
            DelegateChoice {
                roleValue: "tray"
                delegate: WrappedLoader {
                    visible: !root.fullscreen
                    sourceComponent: Tray {}
                }
            }
            DelegateChoice {
                roleValue: "clock"
                delegate: WrappedLoader {
                    visible: !root.fullscreen
                    sourceComponent: Clock {}
                }
            }
            DelegateChoice {
                roleValue: "statusIcons"
                delegate: WrappedLoader {
                    visible: !root.fullscreen
                    sourceComponent: StatusIcons {}
                }
            }
            DelegateChoice {
                roleValue: "power"
                delegate: WrappedLoader {
                    sourceComponent: Power {
                        visibilities: root.visibilities
                    }
                }
            }
        }
    }

    component WrappedLoader: Loader {
        required enabled
        required property string id
        required property int index

        function findFirstEnabled(): Item {
            const count = repeater.count;
            for (let i = 0; i < count; i++) {
                const item = repeater.itemAt(i);
                if (item?.enabled)
                    return item;
            }
            return null;
        }

        function findLastEnabled(): Item {
            for (let i = repeater.count - 1; i >= 0; i--) {
                const item = repeater.itemAt(i);
                if (item?.enabled)
                    return item;
            }
            return null;
        }

        asynchronous: true
        Layout.alignment: root.isVertical ? Qt.AlignHCenter : Qt.AlignVCenter

        // Cursed ahh thing to add padding to first and last enabled components
        Layout.topMargin: root.isVertical && findFirstEnabled() === this ? root.vPadding : 0
        Layout.bottomMargin: root.isVertical && findLastEnabled() === this ? root.vPadding : 0
        Layout.leftMargin: !root.isVertical && findFirstEnabled() === this ? root.vPadding : 0
        Layout.rightMargin: !root.isVertical && findLastEnabled() === this ? root.vPadding : 0

        visible: enabled
        active: enabled
    }
}
