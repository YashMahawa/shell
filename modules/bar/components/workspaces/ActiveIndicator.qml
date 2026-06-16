pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services

StyledRect {
    id: root

    required property int activeWsId
    required property Repeater workspaces
    required property Item mask
    required property bool fullscreen

    readonly property bool isVertical: Config.bar.edge === "left" || Config.bar.edge === "right"
    readonly property int currentWsIdx: {
        let i = activeWsId - 1;
        while (i < 0)
            i += Config.bar.workspaces.shown;
        return i % Config.bar.workspaces.shown;
    }

    property real leading: workspaces.count > 0 ? (isVertical ? workspaces.itemAt(currentWsIdx)?.y : workspaces.itemAt(currentWsIdx)?.x) ?? 0 : 0
    property real trailing: workspaces.count > 0 ? (isVertical ? workspaces.itemAt(currentWsIdx)?.y : workspaces.itemAt(currentWsIdx)?.x) ?? 0 : 0
    property real currentSize: workspaces.count > 0 ? (workspaces.itemAt(currentWsIdx) as Workspace)?.size ?? 0 : 0
    property real offset: Math.min(leading, trailing)
    property real size: {
        const s = Math.abs(leading - trailing) + currentSize;
        if (Config.bar.workspaces.activeTrail && lastWs > currentWsIdx) {
            const ws = workspaces.itemAt(lastWs) as Workspace;
            return ws ? Math.min((isVertical ? ws.y : ws.x) + ws.size - offset, s) : 0;
        }
        return s;
    }

    property int cWs
    property int lastWs

    onCurrentWsIdxChanged: {
        lastWs = cWs;
        cWs = currentWsIdx;
    }

    clip: true
    y: isVertical ? offset + mask.y : mask.y
    x: isVertical ? mask.x : offset + mask.x
    implicitWidth: isVertical ? Tokens.sizes.bar.innerWidth - Tokens.padding.small : size
    implicitHeight: isVertical ? size : Tokens.sizes.bar.innerWidth - Tokens.padding.small
    radius: Tokens.rounding.full
    color: Colours.palette.m3primary

    Colouriser {
        source: root.mask
        sourceColor: Colours.palette.m3onSurface
        colorizationColor: Colours.palette.m3onPrimary

        x: isVertical ? 0 : -parent.offset
        y: isVertical ? -parent.offset : 0
        implicitWidth: root.mask.implicitWidth
        implicitHeight: root.mask.implicitHeight

        anchors.horizontalCenter: isVertical ? parent.horizontalCenter : undefined
        anchors.verticalCenter: !isVertical ? parent.verticalCenter : undefined
    }

    Behavior on leading {
        enabled: root.Config.bar.workspaces.activeTrail

        EAnim {}
    }

    Behavior on trailing {
        enabled: root.Config.bar.workspaces.activeTrail

        EAnim {
            duration: Tokens.anim.durations.normal * 2
        }
    }

    Behavior on currentSize {
        enabled: root.Config.bar.workspaces.activeTrail

        EAnim {}
    }

    Behavior on offset {
        enabled: !root.Config.bar.workspaces.activeTrail

        EAnim {}
    }

    Behavior on size {
        enabled: !root.Config.bar.workspaces.activeTrail

        EAnim {}
    }

    component EAnim: Anim {
        type: Anim.Emphasized
    }
}
