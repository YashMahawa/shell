pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root
    readonly property bool isVertical: Config.bar.edge === "left" || Config.bar.edge === "right"

    required property ShellScreen screen
    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property string activeSpecial: (GlobalConfig.bar.workspaces.perMonitorWorkspaces ? monitor : Hypr.focusedMonitor)?.lastIpcObject.specialWorkspace?.name ?? ""

    layer.enabled: true
    layer.effect: Mask {
        maskSource: mask
    }

    Item {
        id: mask

        anchors.fill: parent
        layer.enabled: true
        visible: false

        Rectangle {
            anchors.fill: parent
            radius: Tokens.rounding.full

            gradient: Gradient {
                orientation: isVertical ? Gradient.Vertical : Gradient.Horizontal

                GradientStop {
                    position: 0
                    color: Qt.rgba(0, 0, 0, 0)
                }
                GradientStop {
                    position: 0.3
                    color: Qt.rgba(0, 0, 0, 1)
                }
                GradientStop {
                    position: 0.7
                    color: Qt.rgba(0, 0, 0, 1)
                }
                GradientStop {
                    position: 1
                    color: Qt.rgba(0, 0, 0, 0)
                }
            }
        }

        Rectangle {
            anchors.top: isVertical ? parent.top : undefined
            anchors.bottom: !isVertical ? parent.bottom : undefined
            anchors.left: parent.left
            anchors.right: isVertical ? parent.right : undefined

            radius: Tokens.rounding.full
            implicitHeight: isVertical ? parent.height / 2 : -1
            implicitWidth: isVertical ? -1 : parent.width / 2
            opacity: (isVertical ? view.contentY : view.contentX) > 0 ? 0 : 1

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.top: !isVertical ? parent.top : undefined
            anchors.right: parent.right
            anchors.left: isVertical ? parent.left : undefined

            radius: Tokens.rounding.full
            implicitHeight: isVertical ? parent.height / 2 : -1
            implicitWidth: isVertical ? -1 : parent.width / 2
            opacity: (isVertical ? view.contentY : view.contentX) < (isVertical ? view.contentHeight - parent.height : view.contentWidth - parent.width) + Tokens.padding.extraSmall ? 0 : 1

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }
    }

    ListView {
        id: view
        orientation: isVertical ? ListView.Vertical : ListView.Horizontal

        anchors.fill: parent
        spacing: Tokens.spacing.medium
        interactive: false

        currentIndex: model.values.findIndex(w => w.name === root.activeSpecial)
        onCurrentIndexChanged: currentIndex = Qt.binding(() => model.values.findIndex(w => w.name === root.activeSpecial))

        model: ScriptModel {
            values: Hypr.workspaces.values.filter(w => w.name.startsWith("special:") && (!GlobalConfig.bar.workspaces.perMonitorWorkspaces || w.monitor === root.monitor))
        }

        preferredHighlightBegin: 0
        preferredHighlightEnd: isVertical ? height : width
        highlightRangeMode: ListView.StrictlyEnforceRange

        highlightFollowsCurrentItem: false
        highlight: Item {
            y: isVertical ? (view.currentItem?.y ?? 0) : 0
            x: isVertical ? 0 : (view.currentItem?.x ?? 0)
            implicitHeight: isVertical ? ((view.currentItem as SpecialWsDelegate)?.size ?? 0) : Tokens.sizes.bar.innerWidth - Tokens.padding.small
            implicitWidth: isVertical ? Tokens.sizes.bar.innerWidth - Tokens.padding.small : ((view.currentItem as SpecialWsDelegate)?.size ?? 0)

            Behavior on y {
                Anim {}
            }
            Behavior on x {
                Anim {}
            }
        }

        delegate: SpecialWsDelegate {}

        add: Transition {
            Anim {
                properties: "scale"
                from: 0
                to: 1
                easing: Tokens.anim.standardDecel
            }
        }

        remove: Transition {
            Anim {
                property: "scale"
                to: 0.5
                type: Anim.StandardSmall
            }
            Anim {
                property: "opacity"
                to: 0
                type: Anim.StandardSmall
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

        displaced: Transition {
            Anim {
                properties: "scale"
                to: 1
                easing: Tokens.anim.standardDecel
            }
            Anim {
                properties: "x,y"
            }
        }
    }

    Loader {
        asynchronous: true
        active: Config.bar.workspaces.activeIndicator
        anchors.fill: parent

        sourceComponent: Item {
            StyledClippingRect {
                id: indicator

                anchors.left: isVertical ? parent.left : undefined
                anchors.right: isVertical ? parent.right : undefined
                anchors.top: !isVertical ? parent.top : undefined
                anchors.bottom: !isVertical ? parent.bottom : undefined

                y: isVertical ? (view.currentItem?.y ?? 0) - view.contentY : 0
                x: isVertical ? 0 : (view.currentItem?.x ?? 0) - view.contentX
                implicitHeight: isVertical ? ((view.currentItem as SpecialWsDelegate)?.size ?? 0) : Tokens.sizes.bar.innerWidth - Tokens.padding.small
                implicitWidth: isVertical ? Tokens.sizes.bar.innerWidth - Tokens.padding.small : ((view.currentItem as SpecialWsDelegate)?.size ?? 0)

                color: Colours.palette.m3tertiary
                radius: Tokens.rounding.full

                Colouriser {
                    source: view
                    sourceColor: Colours.palette.m3onSurface
                    colorizationColor: Colours.palette.m3onTertiary

                    anchors.horizontalCenter: parent.horizontalCenter

                    x: isVertical ? 0 : -indicator.x
                    y: isVertical ? -indicator.y : 0
                    implicitWidth: view.width
                    implicitHeight: view.height
                }

                Behavior on y {
                    Anim {
                        type: Anim.Emphasized
                    }
                }

                Behavior on implicitHeight {
                    Anim {
                        type: Anim.Emphasized
                    }
                }
                Behavior on implicitWidth {
                    Anim {
                        type: Anim.Emphasized
                    }
                }
            }
        }
    }

    MouseArea {
        property real startY

        anchors.fill: view

        drag.target: view.contentItem
        drag.axis: isVertical ? Drag.YAxis : Drag.XAxis
        drag.maximumY: 0
        drag.maximumX: 0
        drag.minimumY: isVertical ? Math.min(0, view.height - view.contentHeight - Tokens.padding.extraSmall) : 0
        drag.minimumX: isVertical ? 0 : Math.min(0, view.width - view.contentWidth - Tokens.padding.extraSmall)

        property real startPos

        onPressed: event => startPos = isVertical ? event.y : event.x

        onClicked: event => {
            if (Math.abs((isVertical ? event.y : event.x) - startPos) > drag.threshold)
                return;

            const ws = view.itemAt(event.x, event.y) as SpecialWsDelegate;
            if (ws?.modelData)
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.workspace.toggle_special("${ws.modelData.name.slice(8)}")` : `togglespecialworkspace ${ws.modelData.name.slice(8)}`);
            else
                Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/caelestia-star-workspace", "toggle", root.monitor.name]);
        }
    }

    component SpecialWsDelegate: GridLayout {
        id: ws
        flow: root.isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight

        required property HyprlandWorkspace modelData
        readonly property int size: (isVertical ? label.Layout.preferredHeight : label.Layout.preferredWidth) + (hasWindows ? (isVertical ? windows.implicitHeight : windows.implicitWidth) + Tokens.padding.extraSmall : 0)
        property int wsId
        property string icon
        property bool hasWindows

        anchors.left: isVertical ? view.contentItem.left : undefined
        anchors.right: isVertical ? view.contentItem.right : undefined
        anchors.top: !isVertical ? view.contentItem.top : undefined
        anchors.bottom: !isVertical ? view.contentItem.bottom : undefined

        rowSpacing: 0
        columnSpacing: 0

        Component.onCompleted: {
            wsId = modelData.id;
            icon = Icons.getSpecialWsIcon(modelData.name);
            hasWindows = Config.bar.workspaces.showWindowsOnSpecialWorkspaces && modelData.lastIpcObject.windows > 0;
        }

        // Hacky thing cause modelData gets destroyed before the remove anim finishes
        Connections {
            function onIdChanged(): void {
                if (ws.modelData)
                    ws.wsId = ws.modelData.id;
            }

            function onNameChanged(): void {
                if (ws.modelData)
                    ws.icon = Icons.getSpecialWsIcon(ws.modelData.name);
            }

            function onLastIpcObjectChanged(): void {
                if (ws.modelData)
                    ws.hasWindows = root.Config.bar.workspaces.showWindowsOnSpecialWorkspaces && ws.modelData.lastIpcObject.windows > 0;
            }

            target: ws.modelData
        }

        Connections {
            function onShowWindowsOnSpecialWorkspacesChanged(): void {
                if (ws.modelData)
                    ws.hasWindows = root.Config.bar.workspaces.showWindowsOnSpecialWorkspaces && ws.modelData.lastIpcObject.windows > 0;
            }

            target: root.Config.bar.workspaces
        }

        Loader {
            id: label

            asynchronous: true

            Layout.alignment: isVertical ? (Qt.AlignHCenter | Qt.AlignTop) : (Qt.AlignVCenter | Qt.AlignLeft)
            Layout.preferredHeight: isVertical ? Tokens.sizes.bar.innerWidth - Tokens.padding.small : -1
            Layout.preferredWidth: isVertical ? -1 : Tokens.sizes.bar.innerWidth - Tokens.padding.small

            sourceComponent: ws.icon.length === 1 ? letterComp : iconComp

            Component {
                id: iconComp

                MaterialIcon {
                    fill: 1
                    text: ws.icon
                    verticalAlignment: Qt.AlignVCenter
                }
            }

            Component {
                id: letterComp

                StyledText {
                    text: ws.icon
                    verticalAlignment: Qt.AlignVCenter
                }
            }
        }

        Loader {
            id: windows

            asynchronous: true

            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: isVertical
            Layout.fillWidth: !isVertical
            Layout.preferredHeight: isVertical ? implicitHeight : -1
            Layout.preferredWidth: isVertical ? -1 : implicitWidth

            visible: active
            active: ws.hasWindows

            sourceComponent: GridLayout {
                flow: root.isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                rowSpacing: 0
                columnSpacing: 0

                Repeater {
                    model: ScriptModel {
                        values: {
                            const windows = Hypr.toplevels.values.filter(c => c.workspace?.id === ws.wsId);
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

            Behavior on Layout.preferredHeight {
                Anim {}
            }
        }
    }
}
