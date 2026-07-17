pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services

StyledRect {
    id: root

    required property var popouts
    readonly property bool isVertical: Config.bar.edge === "left" || Config.bar.edge === "right"

    function linkContains(x: real, y: real): bool {
        const point = linkAction.mapFromItem(root, x, y);
        return linkAction.contains(point);
    }

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
            materialIcon: "content_paste_search"
            colour: Colours.palette.m3secondary
            opensClipboard: true
        }

        ActionIcon {
            id: linkAction
            materialIcon: "hub"
            colour: Colours.palette.m3primary
        }
    }

    component ActionIcon: Item {
        id: action
        property string materialIcon
        property string iconSource
        property bool opensClipboard
        required property color colour
        implicitWidth: 24
        implicitHeight: 24

        StateLayer {
            anchors.fill: parent
            radius: Tokens.rounding.full
            onClicked: {
                if (action.opensClipboard) {
                    root.popouts.hasCurrent = false;
                    Quickshell.execDetached(["caelestia", "shell", "clipboard", "open"]);
                } else {
                    root.popouts.currentName = "continuity";
                    root.popouts.hasCurrent = true;
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
