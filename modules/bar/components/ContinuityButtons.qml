pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services

// Same pattern as StatusIcons (wifi/bluetooth): hover opens side popout via Bar.checkPopout.
// Click on clipboard opens the center clipboard panel.
StyledRect {
    id: root

    required property var popouts
    property var bar: null
    readonly property bool linkEnabled: true
    readonly property bool isVertical: Config.bar.edge === "left" || Config.bar.edge === "right"

    function clipboardContains(x: real, y: real): bool {
        const point = clipboardAction.mapFromItem(root, x, y);
        const pad = 10;
        return point.x >= -pad && point.y >= -pad
            && point.x <= clipboardAction.width + pad
            && point.y <= clipboardAction.height + pad;
    }

    function linkContains(x: real, y: real): bool {
        if (!linkEnabled)
            return false;
        const point = linkAction.mapFromItem(root, x, y);
        const pad = 10;
        return point.x >= -pad && point.y >= -pad
            && point.x <= linkAction.width + pad
            && point.y <= linkAction.height + pad;
    }

    function setCenterFor(action: Item): void {
        if (!root.bar)
            return;
        const mapped = action.mapToItem(root.bar, isVertical ? 0 : action.implicitWidth / 2, isVertical ? action.implicitHeight / 2 : 0);
        root.popouts.currentCenter = mapped[isVertical ? "y" : "x"] ?? 0;
    }

    function setClipboardCenter(): void { setCenterFor(clipboardAction); }
    function setLinkCenter(): void { setCenterFor(linkAction); }

    color: Colours.layer(Colours.palette.m3surfaceContainer, 0.86)
    radius: Tokens.rounding.full
    implicitWidth: isVertical ? Tokens.sizes.bar.innerWidth : icons.implicitWidth + Tokens.padding.small * 2
    implicitHeight: isVertical ? icons.implicitHeight + Tokens.padding.small * 2 : Tokens.sizes.bar.innerWidth

    GridLayout {
        id: icons
        anchors.centerIn: parent
        flow: root.isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rowSpacing: 2
        columnSpacing: 2

        ActionIcon {
            id: clipboardAction
            materialIcon: "content_paste_search"
            colour: Colours.palette.m3secondary
            opensClipboard: true
        }

        ActionIcon {
            id: linkAction
            visible: root.linkEnabled
            Layout.preferredWidth: visible ? implicitWidth : 0
            Layout.preferredHeight: visible ? implicitHeight : 0
            materialIcon: "hub"
            colour: Colours.palette.m3primary
        }
    }

    component ActionIcon: Item {
        id: action
        property string materialIcon
        property string iconSource
        property bool opensClipboard: false
        required property color colour
        implicitWidth: 28
        implicitHeight: 28

        StateLayer {
            anchors.fill: parent
            radius: Tokens.rounding.full
            onClicked: {
                if (action.opensClipboard) {
                    // Click → center clipboard (like opening settings from a popout).
                    if (root.popouts.isDetached && root.popouts.detachedMode === "clipboard")
                        root.popouts.close();
                    else if (typeof root.popouts.detach === "function")
                        root.popouts.detach("clipboard");
                    else
                        Quickshell.execDetached(["caelestia", "shell", "clipboard", "open"]);
                } else {
                    // Click Link → centered, keyboard-safe Caelestia window.
                    root.popouts.linkPage = "overview";
                    root.popouts.detach("link");
                }
            }
        }

        Loader {
            anchors.centerIn: parent
            sourceComponent: action.iconSource ? sourceIcon : material
        }
        Component {
            id: material
            MaterialIcon {
                text: action.materialIcon
                color: action.colour
                fontStyle: Tokens.font.icon.small
                fill: 1
                renderType: Text.NativeRendering
            }
        }
        Component {
            id: sourceIcon
            ColouredIcon {
                source: action.iconSource
                implicitSize: 18
                colour: action.colour
            }
        }
    }
}
