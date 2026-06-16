pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.utils
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property ShellScreen screen
    required property DrawerVisibilities visibilities
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen

    readonly property bool disabled: Strings.testRegexList(Config.bar.excludedScreens, screen.name)

    readonly property bool isVertical: Config.bar.edge === "left" || Config.bar.edge === "right"
    readonly property int clampedThickness: Math.max(Config.border.minThickness, isVertical ? implicitWidth : implicitHeight)
    readonly property int padding: Math.max(Tokens.padding.small, Config.border.thickness)
    readonly property int contentThickness: Tokens.sizes.bar.innerWidth + padding * 2
    readonly property int exclusiveZone: !disabled && (Config.bar.persistent || visibilities.bar) ? contentThickness : Config.border.thickness
    readonly property bool shouldBeVisible: !fullscreen && !disabled && (Config.bar.persistent || visibilities.bar || isHovered)
    property bool isHovered

    function closeTray(): void {
        (content.item as Bar)?.closeTray();
    }

    function checkPopout(x: real, y: real): void {
        (content.item as Bar)?.checkPopout(x, y);
    }

    function handleWheel(x: real, y: real, angleDelta: point): void {
        (content.item as Bar)?.handleWheel(x, y, angleDelta);
    }

    clip: true
    visible: (isVertical ? width : height) > Config.border.thickness
    implicitWidth: fullscreen ? 0 : (isVertical ? Config.border.thickness : -1)
    implicitHeight: fullscreen ? 0 : (isVertical ? -1 : Config.border.thickness)

    states: State {
        name: "visible"
        when: root.shouldBeVisible

        PropertyChanges {
            root.implicitWidth: root.isVertical ? root.contentThickness : root.implicitWidth
            root.implicitHeight: !root.isVertical ? root.contentThickness : root.implicitHeight
        }
    }

    transitions: [
        Transition {
            from: ""
            to: "visible"

            Anim {
                target: root
                properties: "implicitWidth,implicitHeight"
            }
        },
        Transition {
            from: "visible"
            to: ""

            Anim {
                target: root
                properties: "implicitWidth,implicitHeight"
                type: Anim.Emphasized
            }
        }
    ]

    Loader {
        id: content

        anchors.top: Config.bar.edge === "bottom" ? undefined : parent.top
        anchors.bottom: Config.bar.edge === "top" ? undefined : parent.bottom
        anchors.left: Config.bar.edge === "right" ? undefined : parent.left
        anchors.right: Config.bar.edge === "left" ? undefined : parent.right

        active: root.shouldBeVisible

        sourceComponent: Bar {
            width: root.isVertical ? root.contentThickness : -1
            height: root.isVertical ? -1 : root.contentThickness
            screen: root.screen
            visibilities: root.visibilities
            popouts: root.popouts // qmllint disable incompatible-type
            fullscreen: root.fullscreen
        }
    }
}
