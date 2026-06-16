pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.modules.bar.popouts // Need to import this module so the Wrapper type is the same as others

Item {
    id: root
    readonly property bool isVertical: Config.bar.edge === "left" || Config.bar.edge === "right"

    required property ShellScreen screen
    required property real borderThickness

    readonly property alias content: content
    property real offsetScale: content.hasCurrent || content.isDetached ? 0 : 1

    visible: width > 0 && height > 0
    clip: true

    implicitWidth: isVertical ? content.implicitWidth * (1 - offsetScale) : content.implicitWidth
    implicitHeight: isVertical ? content.implicitHeight : content.implicitHeight * (1 - offsetScale)

    x: {
        if (content.isDetached)
            return (parent.width - content.nonAnimWidth) / 2;
        if (isVertical) {
            return Config.bar.edge === "right" ? parent.width - implicitWidth : 0;
        }
        const off = content.currentCenter - borderThickness - content.nonAnimWidth / 2;
        const diff = parent.width - Math.floor(off + content.nonAnimWidth);
        if (diff < 0) return off + diff;
        return Math.max(off, 0);
    }
    y: {
        if (content.isDetached)
            return (parent.height - content.nonAnimHeight) / 2;
        if (!isVertical) {
            return Config.bar.edge === "bottom" ? parent.height - implicitHeight : 0;
        }
        const off = content.currentCenter - borderThickness - content.nonAnimHeight / 2;
        const diff = parent.height - Math.floor(off + content.nonAnimHeight);
        if (diff < 0) return off + diff;
        return Math.max(off, 0);
    }

    Behavior on offsetScale {
        Anim {}
    }

    Behavior on x {
        Anim {
            duration: content.animLength
            easing: content.animCurve
        }
    }

    Behavior on y {
        enabled: root.offsetScale < 1

        Anim {
            duration: content.animLength
            easing: content.animCurve
        }
    }

    Wrapper {
        id: content

        screen: root.screen
        offsetScale: root.offsetScale

        anchors.left: isVertical && Config.bar.edge === "left" ? parent.left : undefined
        anchors.right: isVertical && Config.bar.edge === "right" ? parent.right : undefined
        anchors.top: !isVertical && Config.bar.edge === "top" ? parent.top : undefined
        anchors.bottom: !isVertical && Config.bar.edge === "bottom" ? parent.bottom : undefined

        anchors.verticalCenter: isVertical ? parent.verticalCenter : undefined
        anchors.horizontalCenter: !isVertical ? parent.horizontalCenter : undefined

        anchors.leftMargin: isVertical && Config.bar.edge === "left" ? (-implicitWidth - 5) * root.offsetScale : 0
        anchors.rightMargin: isVertical && Config.bar.edge === "right" ? (-implicitWidth - 5) * root.offsetScale : 0
        anchors.topMargin: !isVertical && Config.bar.edge === "top" ? (-implicitHeight - 5) * root.offsetScale : 0
        anchors.bottomMargin: !isVertical && Config.bar.edge === "bottom" ? (-implicitHeight - 5) * root.offsetScale : 0
    }
}
