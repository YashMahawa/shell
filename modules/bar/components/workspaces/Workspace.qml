pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

GridLayout {
    id: root
    readonly property bool isVertical: Config.bar.edge === "left" || Config.bar.edge === "right"
    flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight

    required property int index
    required property int activeWsId
    required property var occupied
    required property int groupOffset

    readonly property bool isWorkspace: true // Flag for finding workspace children
    // Unanimated prop for others to use as reference
    readonly property int size: (isVertical ? implicitHeight : implicitWidth) + (hasWindows ? Tokens.padding.extraSmall : 0)

    readonly property int ws: groupOffset + index + 1
    readonly property bool isOccupied: occupied[ws] ?? false
    readonly property bool hasWindows: isOccupied && Config.bar.workspaces.showWindows

    Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
    Layout.preferredHeight: isVertical ? size : -1
    Layout.preferredWidth: isVertical ? -1 : size

    rowSpacing: 0
    columnSpacing: 0

    StyledText {
        id: indicator

        Layout.alignment: isVertical ? (Qt.AlignHCenter | Qt.AlignTop) : (Qt.AlignVCenter | Qt.AlignLeft)
        Layout.preferredHeight: isVertical ? Tokens.sizes.bar.innerWidth - Tokens.padding.small : -1
        Layout.preferredWidth: isVertical ? -1 : Tokens.sizes.bar.innerWidth - Tokens.padding.small
        horizontalAlignment: isVertical ? Text.AlignHCenter : Text.AlignHCenter

        animate: true
        text: {
            const ws = Hypr.workspaces.values.find(w => w.id === root.ws);
            const wsName = !ws || ws.name == root.ws ? root.ws : ws.name[0];
            let displayName = wsName.toString();
            if (Config.bar.workspaces.capitalisation.toLowerCase() === "upper") {
                displayName = displayName.toUpperCase();
            } else if (Config.bar.workspaces.capitalisation.toLowerCase() === "lower") {
                displayName = displayName.toLowerCase();
            }
            const label = Config.bar.workspaces.label || displayName;
            const occupiedLabel = Config.bar.workspaces.occupiedLabel || label;
            const activeLabel = Config.bar.workspaces.activeLabel || (root.isOccupied ? occupiedLabel : label);
            return root.activeWsId === root.ws ? activeLabel : root.isOccupied ? occupiedLabel : label;
        }
        color: Config.bar.workspaces.occupiedBg || root.isOccupied || root.activeWsId === root.ws ? Colours.palette.m3onSurface : Colours.layer(Colours.palette.m3outlineVariant, 2)
        verticalAlignment: Qt.AlignVCenter
        font.family: Tokens.font.workspaces
    }

    Loader {
        id: windows

        asynchronous: true

        Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
        Layout.fillHeight: isVertical
        Layout.fillWidth: !isVertical
        Layout.topMargin: isVertical ? -Tokens.sizes.bar.innerWidth / 10 : 0
        Layout.leftMargin: !isVertical ? -Tokens.sizes.bar.innerWidth / 10 : 0

        visible: active
        active: root.hasWindows

        sourceComponent: GridLayout {
            flow: root.isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
            rowSpacing: 0
            columnSpacing: 0

            Repeater {
                model: ScriptModel {
                    values: {
                        const ws = root.ws;
                        const windows = Hypr.toplevels.values.filter(c => c.workspace?.id === ws);
                        const maxIcons = root.Config.bar.workspaces.maxWindowIcons;
                        return maxIcons > 0 ? windows.slice(0, maxIcons) : windows;
                    }
                }

                MaterialIcon {
                    required property var modelData

                    grade: 0
                    text: Icons.getAppCategoryIcon(modelData.lastIpcObject.class, "terminal")
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }

    Behavior on Layout.preferredHeight {
        Anim {}
    }
    Behavior on Layout.preferredWidth {
        Anim {}
    }
}
