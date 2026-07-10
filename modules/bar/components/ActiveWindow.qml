pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

Item {
    id: root
    readonly property bool isVertical: Config.bar.edge === "left" || Config.bar.edge === "right"

    required property var bar
    required property Brightness.Monitor monitor
    property color colour: Colours.palette.m3primary

    readonly property string windowTitle: {
        const title = Hypr.activeToplevel?.title;
        if (!title)
            return qsTr("Desktop");
        if (Config.bar.activeWindow.compact) {
            // " - " (standard hyphen), " — " (em dash), " – " (en dash)
            const parts = title.split(/\s+[\-\u2013\u2014]\s+/);
            if (parts.length > 1)
                return parts[parts.length - 1].trim();
        }
        return title;
    }

    readonly property int maxSize: {
        const otherModules = bar.children.filter(c => c.id && c.item !== this && c.id !== "spacer");
        const otherSize = otherModules.reduce((acc, curr) => acc + (isVertical ? (curr.item.nonAnimHeight ?? curr.height) : (curr.item.nonAnimWidth ?? curr.width)), 0);
        // Length - 2 cause repeater counts as a child
        return (isVertical ? bar.height : bar.width) - otherSize - (isVertical ? bar.rowSpacing : bar.columnSpacing) * (bar.children.length - 1) - bar.vPadding * 2;
    }
    property Title current: text1

    clip: true
    implicitWidth: isVertical ? Math.max(icon.implicitWidth, current.implicitHeight) : icon.implicitWidth + current.implicitWidth + current.anchors.leftMargin
    implicitHeight: isVertical ? icon.implicitHeight + current.implicitWidth + current.anchors.topMargin : Math.max(icon.implicitHeight, current.implicitHeight)

    Loader {
        asynchronous: true
        anchors.fill: parent
        active: !Config.bar.activeWindow.showOnHover

        sourceComponent: MouseArea {
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onPositionChanged: {
                const popouts = root.bar.popouts;
                if (popouts.hasCurrent && popouts.currentName !== "activewindow")
                    popouts.hasCurrent = false;
            }
            onClicked: {
                const popouts = root.bar.popouts;
                if (popouts.hasCurrent) {
                    popouts.hasCurrent = false;
                } else {
                    popouts.currentName = "activewindow";
                    popouts.currentCenter = root.mapToItem(root.bar, isVertical ? 0 : root.implicitWidth / 2, isVertical ? root.implicitHeight / 2 : 0)[isVertical ? "y" : "x"];
                    popouts.hasCurrent = true;
                }
            }
        }
    }

    MaterialIcon {
        id: icon

        anchors.horizontalCenter: isVertical ? parent.horizontalCenter : undefined
        anchors.verticalCenter: !isVertical ? parent.verticalCenter : undefined

        animate: true
        text: Icons.getAppCategoryIcon(Hypr.activeToplevel?.lastIpcObject.class, "desktop_windows")
        color: root.colour
    }

    Title {
        id: text1
    }

    Title {
        id: text2
    }

    TextMetrics {
        id: metrics

        text: root.windowTitle
        font: root.Tokens.font.body.builders.small.letterSpacing(1.4).build()
        elide: Qt.ElideRight
        elideWidth: root.maxSize - (isVertical ? icon.height : icon.width)

        onTextChanged: {
            const next = root.current === text1 ? text2 : text1;
            next.text = elidedText;
            root.current = next;
        }
        onElideWidthChanged: root.current.text = elidedText
    }

    Behavior on implicitHeight {
        Anim {}
    }

    component Title: StyledText {
        id: text

        anchors.horizontalCenter: root.isVertical ? icon.horizontalCenter : undefined
        anchors.verticalCenter: !root.isVertical ? icon.verticalCenter : undefined
        anchors.top: root.isVertical ? icon.bottom : undefined
        anchors.left: !root.isVertical ? icon.right : undefined
        anchors.topMargin: root.isVertical ? Tokens.spacing.small : 0
        anchors.leftMargin: !root.isVertical ? Tokens.spacing.small : 0

        font: metrics.font
        color: root.colour
        opacity: root.current === this ? 1 : 0
        horizontalAlignment: Text.AlignLeft

        transform: [
            Translate {
                x: root.isVertical && root.Config.bar.activeWindow.inverted ? -text.implicitWidth + text.implicitHeight : 0
                y: !root.isVertical && root.Config.bar.activeWindow.inverted ? text.implicitHeight : 0
            },
            Rotation {
                angle: root.isVertical ? (root.Config.bar.activeWindow.inverted ? 270 : 90) : 0
                origin.x: root.isVertical ? text.implicitHeight / 2 : 0
                origin.y: root.isVertical ? text.implicitHeight / 2 : 0
            }
        ]

        width: root.isVertical ? implicitHeight : implicitWidth
        height: root.isVertical ? implicitWidth : implicitHeight

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
