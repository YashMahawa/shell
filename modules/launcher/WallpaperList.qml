pragma ComponentBehavior: Bound

import "items"
import QtQuick
import Quickshell
import Caelestia.Config
import qs.components.controls
import qs.services

PathView {
    id: root

    required property StyledTextField search
    required property var visibilities
    required property var panels
    required property var content

    readonly property int itemWidth: Tokens.sizes.launcher.wallpaperWidth * 0.8 + Tokens.padding.medium * 2
    property real wheelAccumulator: 0
    property bool userSelecting: false

    function commitCurrentSelection(): void {
        if (!userSelecting)
            return;

        const item = scriptModel.values[currentIndex];
        userSelecting = false;
        if (item && item.path !== Wallpapers.actualCurrent)
            Wallpapers.setWallpaper(item.path);
    }

    readonly property int numItems: {
        const screen = (QsWindow.window as QsWindow)?.screen;
        if (!screen)
            return 0;

        // Screen width - 4x outer rounding - 2x max side thickness (cause centered)
        const barMargins = Math.max(Config.border.thickness, panels.bar.implicitWidth);
        let outerMargins = 0;
        if (panels.popouts.hasCurrent && panels.popouts.currentCenter + panels.popouts.nonAnimHeight / 2 > screen.height - content.implicitHeight - Config.border.thickness * 2)
            outerMargins = panels.popouts.nonAnimWidth;
        if ((visibilities.utilities || visibilities.sidebar) && panels.utilities.implicitWidth > outerMargins)
            outerMargins = panels.utilities.implicitWidth;
        const maxWidth = screen.width - Config.border.rounding * 4 - (barMargins + outerMargins) * 2;

        if (maxWidth <= 0)
            return 0;

        const maxItemsOnScreen = Math.floor(maxWidth / itemWidth);
        const visible = Math.min(maxItemsOnScreen, Config.launcher.maxWallpapers, scriptModel.values.length);

        if (visible === 2)
            return 1;
        if (visible > 1 && visible % 2 === 0)
            return visible - 1;
        return visible;
    }

    model: ScriptModel {
        id: scriptModel

        readonly property string search: root.search.text.split(" ").slice(1).join(" ")

        values: Wallpapers.query(search)
        onValuesChanged: {
            selectionCommit.stop();
            root.userSelecting = false;
            const index = search ? 0 : values.findIndex(w => w.path === Wallpapers.actualCurrent);
            root.currentIndex = Math.max(0, index);
        }
    }

    Component.onCompleted: currentIndex = Math.max(0, Wallpapers.list.findIndex(w => w.path === Wallpapers.actualCurrent))
    Component.onDestruction: {
        commitCurrentSelection();
        Wallpapers.stopPreview();
    }

    Timer {
        id: previewDebounce

        interval: 140
        repeat: false
        onTriggered: {
            const item = scriptModel.values[root.currentIndex];
            if (item)
                Wallpapers.preview(item.path);
        }
    }

    onCurrentIndexChanged: {
        previewDebounce.restart();
        if (userSelecting)
            selectionCommit.restart();
    }
    onDraggingChanged: {
        if (dragging)
            userSelecting = true;
    }
    onMovementEnded: selectionCommit.restart()

    Timer {
        id: selectionCommit

        interval: 650
        repeat: false
        onTriggered: root.commitCurrentSelection()
    }

    implicitWidth: Math.min(numItems, count) * itemWidth
    pathItemCount: numItems
    cacheItemCount: 6

    snapMode: PathView.SnapToItem
    preferredHighlightBegin: 0.5
    preferredHighlightEnd: 0.5
    highlightRangeMode: PathView.StrictlyEnforceRange
    highlightMoveDuration: 320
    flickDeceleration: 4200
    maximumFlickVelocity: 3600

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton

        onWheel: wheel => {
            const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y * 3;
            root.userSelecting = true;
            root.wheelAccumulator += delta;

            while (Math.abs(root.wheelAccumulator) >= 120) {
                if (root.wheelAccumulator < 0)
                    root.incrementCurrentIndex();
                else
                    root.decrementCurrentIndex();
                root.wheelAccumulator += root.wheelAccumulator < 0 ? 120 : -120;
            }

            wheel.accepted = true;
            wheelReset.restart();
        }
    }

    Timer {
        id: wheelReset
        interval: 180
        onTriggered: root.wheelAccumulator = 0
    }

    delegate: WallpaperItem {
        visibilities: root.visibilities
    }

    path: Path {
        startY: root.height / 2

        PathAttribute {
            name: "z"
            value: 0
        }
        PathAttribute {
            name: "itemScale"
            value: 0.74
        }
        PathAttribute {
            name: "itemOpacity"
            value: 0.68
        }
        PathLine {
            x: root.width / 2
            relativeY: 0
        }
        PathAttribute {
            name: "z"
            value: 2
        }
        PathAttribute {
            name: "itemScale"
            value: 1
        }
        PathAttribute {
            name: "itemOpacity"
            value: 1
        }
        PathLine {
            x: root.width
            relativeY: 0
        }
        PathAttribute {
            name: "z"
            value: 0
        }
        PathAttribute {
            name: "itemScale"
            value: 0.74
        }
        PathAttribute {
            name: "itemOpacity"
            value: 0.68
        }
    }
}
