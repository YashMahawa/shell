pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    readonly property alias layout: layout
    readonly property alias items: items
    readonly property alias expandIcon: expandIcon

    readonly property int padding: Config.bar.tray.background ? Tokens.padding.medium : Tokens.padding.extraSmall
    readonly property int spacing: Config.bar.tray.background ? Tokens.spacing.small : 0
    readonly property bool isVertical: Config.bar.edge === "left" || Config.bar.edge === "right"

    property bool expanded

    readonly property real nonAnimSize: {
        if (!Config.bar.tray.compact)
            return (isVertical ? layout.implicitHeight : layout.implicitWidth) + padding * 2;
        const expandIconSize = isVertical ? expandIcon.implicitHeight : expandIcon.implicitWidth;
        const layoutSize = isVertical ? layout.implicitHeight : layout.implicitWidth;
        return (expanded ? expandIconSize + layoutSize + spacing : expandIconSize) + padding * 2;
    }

    clip: true
    visible: height > 0

    implicitWidth: isVertical ? Tokens.sizes.bar.innerWidth : nonAnimSize
    implicitHeight: isVertical ? nonAnimSize : Tokens.sizes.bar.innerWidth

    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, (Config.bar.tray.background && items.count > 0) ? Colours.tPalette.m3surfaceContainer.a : 0)
    radius: Tokens.rounding.full

    GridLayout {
        id: layout
        flow: root.isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight

        anchors.horizontalCenter: root.isVertical ? parent.horizontalCenter : undefined
        anchors.verticalCenter: !root.isVertical ? parent.verticalCenter : undefined
        anchors.top: root.isVertical ? parent.top : undefined
        anchors.left: !root.isVertical ? parent.left : undefined
        anchors.topMargin: root.isVertical ? root.padding : 0
        anchors.leftMargin: !root.isVertical ? root.padding : 0
        rowSpacing: Tokens.spacing.small
        columnSpacing: Tokens.spacing.small

        opacity: root.expanded || !Config.bar.tray.compact ? 1 : 0

        add: Transition {
            Anim {
                properties: "scale"
                from: 0
                to: 1
                easing: Tokens.anim.standardDecel
            }
        }

        move: Transition {
            Anim {
                properties: "scale"
                to: 1
                easing: Tokens.anim.standardDecel
            }
            Anim {
                properties: "x,y"
            }
        }

        Repeater {
            id: items

            model: ScriptModel {
                values: SystemTray.items.values.filter(i => !GlobalConfig.bar.tray.hiddenIcons.includes(i.id))
            }

            TrayItem {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        id: expandIcon

        asynchronous: true

        anchors.horizontalCenter: root.isVertical ? parent.horizontalCenter : undefined
        anchors.verticalCenter: !root.isVertical ? parent.verticalCenter : undefined
        anchors.bottom: root.isVertical ? parent.bottom : undefined
        anchors.right: !root.isVertical ? parent.right : undefined

        active: Config.bar.tray.compact && items.count > 0

        sourceComponent: Item {
            implicitWidth: expandIconInner.implicitWidth
            implicitHeight: expandIconInner.implicitHeight - Tokens.padding.small

            MaterialIcon {
                id: expandIconInner

                anchors.horizontalCenter: root.isVertical ? parent.horizontalCenter : undefined
                anchors.verticalCenter: !root.isVertical ? parent.verticalCenter : undefined
                anchors.bottom: root.isVertical ? parent.bottom : undefined
                anchors.right: !root.isVertical ? parent.right : undefined
                anchors.bottomMargin: root.isVertical ? (Config.bar.tray.background ? Tokens.padding.extraSmall : -Tokens.padding.extraSmall) : 0
                anchors.rightMargin: !root.isVertical ? (Config.bar.tray.background ? Tokens.padding.extraSmall : -Tokens.padding.extraSmall) : 0
                text: "expand_less"
                fontStyle: Tokens.font.icon.large
                rotation: root.expanded ? (root.isVertical ? 180 : -90) : (root.isVertical ? 0 : 90)

                Behavior on rotation {
                    Anim {}
                }

                Behavior on anchors.bottomMargin {
                    Anim {}
                }
                Behavior on anchors.rightMargin {
                    Anim {}
                }
            }
        }
    }

    Behavior on implicitHeight {
        Anim {}
    }
    Behavior on implicitWidth {
        Anim {}
    }
}
