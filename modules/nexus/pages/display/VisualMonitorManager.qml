pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Interactive Monitor Manager")

    property NexusState nState: null
    property var monitorsData: []
    property int selectedIndex: 0
    property var selectedMonitor: monitorsData[selectedIndex] ?? null
    property var profilesList: []
    property string newProfileName: ""
    property string pendingToken: ""
    property int revertSeconds: 20
    property string statusMessage: ""
    property bool statusIsError: false

    property real snapGuideX: -1
    property real snapGuideY: -1
    property bool snapGuideXActive: false
    property bool snapGuideYActive: false

    readonly property list<MenuItem> scaleItems: [
        MenuItem { text: "100%" },
        MenuItem { text: "125%" },
        MenuItem { text: "150%" },
        MenuItem { text: "175%" },
        MenuItem { text: "200%" }
    ]

    readonly property list<MenuItem> orientationItems: [
        MenuItem { text: qsTr("Landscape") },
        MenuItem { text: qsTr("Portrait left") },
        MenuItem { text: qsTr("Landscape flipped") },
        MenuItem { text: qsTr("Portrait right") }
    ]

    function calculateLogicalW(m: var): real {
        if (!m) return 1920;
        const scale = Math.max(m.scale || 1, 0.25);
        const transform = m.transform || 0;
        return (transform % 2 === 1) ? ((m.height || 1080) / scale) : ((m.width || 1920) / scale);
    }

    function calculateLogicalH(m: var): real {
        if (!m) return 1080;
        const scale = Math.max(m.scale || 1, 0.25);
        const transform = m.transform || 0;
        return (transform % 2 === 1) ? ((m.width || 1920) / scale) : ((m.height || 1080) / scale);
    }

    function getBounds(): var {
        if (!monitorsData || monitorsData.length === 0)
            return { minX: 0, maxX: 1920, minY: 0, maxY: 1080, totalW: 1920, totalH: 1080 };

        let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
        for (let i = 0; i < monitorsData.length; i++) {
            const m = monitorsData[i];
            const w = calculateLogicalW(m);
            const h = calculateLogicalH(m);
            minX = Math.min(minX, m.x || 0);
            maxX = Math.max(maxX, (m.x || 0) + w);
            minY = Math.min(minY, m.y || 0);
            maxY = Math.max(maxY, (m.y || 0) + h);
        }
        if (!Number.isFinite(minX)) minX = 0;
        if (!Number.isFinite(maxX)) maxX = 1920;
        if (!Number.isFinite(minY)) minY = 0;
        if (!Number.isFinite(maxY)) maxY = 1080;

        return {
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
            totalW: Math.max(maxX - minX, 100),
            totalH: Math.max(maxY - minY, 100)
        };
    }

    function getScaleFactor(cWidth: real, cHeight: real): real {
        const bounds = getBounds();
        const availableW = Math.max(cWidth - 100, 100);
        const availableH = Math.max(cHeight - 100, 100);
        return Math.min(availableW / bounds.totalW, availableH / bounds.totalH);
    }

    function getCanvasX(logicalX: real, scaleFactor: real, minX: real, cWidth: real, totalW: real): real {
        const offsetX = (cWidth - totalW * scaleFactor) / 2 - minX * scaleFactor;
        return logicalX * scaleFactor + offsetX;
    }

    function getCanvasY(logicalY: real, scaleFactor: real, minY: real, cHeight: real, totalH: real): real {
        const offsetY = (cHeight - totalH * scaleFactor) / 2 - minY * scaleFactor;
        return logicalY * scaleFactor + offsetY;
    }

    function updateMonitorsFromHypr(): void {
        const liveMonitors = Hypr.monitors.values;
        const result = [];
        for (let i = 0; i < liveMonitors.length; i++) {
            const m = liveMonitors[i];
            result.push({
                name: m.name,
                description: m.description || m.name,
                width: m.width || 1920,
                height: m.height || 1080,
                refreshRate: Math.round((m.refreshRate || 60) * 100) / 100,
                scale: m.scale || 1,
                transform: m.transform || 0,
                x: m.x || 0,
                y: m.y || 0,
                disabled: false
            });
        }
        if (result.length === 0) {
            result.push({
                name: "eDP-1",
                description: "Built-in Laptop Screen",
                width: 1920,
                height: 1080,
                refreshRate: 60,
                scale: 1.25,
                transform: 0,
                x: 0,
                y: 0,
                disabled: false
            });
            result.push({
                name: "HDMI-A-1",
                description: "External Desktop Display",
                width: 2560,
                height: 1440,
                refreshRate: 144,
                scale: 1.0,
                transform: 0,
                x: 1536,
                y: 0,
                disabled: false
            });
        }
        monitorsData = result;
        if (selectedIndex >= monitorsData.length)
            selectedIndex = 0;
    }

    function formatMonitorsPayload(): var {
        const payload = [];
        for (let i = 0; i < monitorsData.length; i++) {
            const m = monitorsData[i];
            payload.push({
                name: m.name,
                res: `${m.width}x${m.height}@${m.refreshRate}`,
                pos: `${m.x}x${m.y}`,
                scale: String(m.scale),
                transform: String(m.transform),
                disabled: !!m.disabled
            });
        }
        return payload;
    }

    function applyLayout(): void {
        const payload = JSON.stringify(formatMonitorsPayload());
        root.statusMessage = qsTr("Applying spatial layout…");
        root.statusIsError = false;
        applyProc.exec(["caelestia-display", "apply", "--monitors-json", payload]);
    }

    function loadProfiles(): void {
        profileProc.exec(["caelestia-display", "profile", "list"]);
    }

    function saveCurrentProfile(): void {
        if (!newProfileName.trim()) {
            root.statusMessage = qsTr("Please enter a profile name first.");
            root.statusIsError = true;
            return;
        }
        const payload = JSON.stringify(formatMonitorsPayload());
        saveProfileProc.exec(["caelestia-display", "profile", "save", newProfileName.trim(), "--monitors-json", payload]);
    }

    Component.onCompleted: {
        updateMonitorsFromHypr();
        loadProfiles();
    }

    Process {
        id: applyProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const res = JSON.parse(text);
                    root.pendingToken = res.token ?? "";
                    root.revertSeconds = res.timeout ?? 20;
                    root.statusMessage = qsTr("Spatial layout applied. Confirm within %1 seconds.").arg(root.revertSeconds);
                    root.statusIsError = false;
                    revertTimer.restart();
                } catch (error) {
                    if (text.trim()) root.statusMessage = text.trim();
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim()) {
                    root.statusMessage = text.trim();
                    root.statusIsError = true;
                }
            }
        }
        onExited: Hyprland.refreshMonitors()
    }

    Process {
        id: confirmProc

        stdout: StdioCollector {
            onStreamFinished: {
                root.statusMessage = qsTr("Spatial arrangement profile confirmed and saved!");
                root.statusIsError = false;
                root.pendingToken = "";
                revertTimer.stop();
            }
        }
    }

    Process {
        id: rollbackProc

        stdout: StdioCollector {
            onStreamFinished: {
                root.statusMessage = qsTr("Reverted to previous monitor spatial layout.");
                root.statusIsError = false;
                root.pendingToken = "";
                revertTimer.stop();
                Hyprland.refreshMonitors();
                updateMonitorsFromHypr();
            }
        }
    }

    Process {
        id: profileProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.profilesList = data.profiles ?? [];
                } catch (error) {}
            }
        }
    }

    Process {
        id: saveProfileProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.profilesList = data.profiles ?? [];
                    root.newProfileName = "";
                    root.statusMessage = qsTr("Profile saved successfully!");
                    root.statusIsError = false;
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadProfileProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const res = JSON.parse(text);
                    root.pendingToken = res.token ?? "";
                    root.revertSeconds = res.timeout ?? 20;
                    root.statusMessage = qsTr("Profile layout loaded. Confirm within %1 seconds.").arg(root.revertSeconds);
                    root.statusIsError = false;
                    revertTimer.restart();
                } catch (e) {}
            }
        }
        onExited: {
            Hyprland.refreshMonitors();
            updateMonitorsFromHypr();
        }
    }

    Process {
        id: deleteProfileProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.profilesList = data.profiles ?? [];
                    root.statusMessage = qsTr("Profile deleted.");
                    root.statusIsError = false;
                } catch (e) {}
            }
        }
    }

    Timer {
        id: revertTimer

        interval: 1000
        repeat: true
        onTriggered: {
            root.revertSeconds--;
            if (root.revertSeconds <= 0) {
                stop();
                rollbackProc.exec(["caelestia-display", "rollback", root.pendingToken]);
            } else {
                root.statusMessage = qsTr("Confirm spatial layout within %1 seconds").arg(root.revertSeconds);
            }
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            TextButton {
                text: qsTr("← Back to Display Settings")
                onClicked: {
                    if (root.nState)
                        root.nState.closeSubPage();
                }
            }

            Item { Layout.fillWidth: true }

            StyledText {
                text: qsTr("Drag displays or enter precise coordinates")
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }

        // Section 1: Interactive Spatial Canvas Viewport
        SectionHeader { text: qsTr("Spatial Arrangement Canvas") }

        StyledRect {
            id: canvasBox

            Layout.fillWidth: true
            implicitHeight: 340
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainerLow
            border.width: 1
            border.color: Colours.palette.m3outlineVariant
            clip: true

            // Grid pattern background
            Repeater {
                model: Math.floor(canvasBox.implicitHeight / 40)
                delegate: Rectangle {
                    required property int index
                    y: index * 40
                    width: parent.width
                    height: 1
                    color: Colours.palette.m3outlineVariant
                    opacity: 0.15
                }
            }
            Repeater {
                model: Math.floor(800 / 40)
                delegate: Rectangle {
                    required property int index
                    x: index * 40
                    height: parent.height
                    width: 1
                    color: Colours.palette.m3outlineVariant
                    opacity: 0.15
                }
            }

            // Magnetic Snap Guide Lines
            Rectangle {
                visible: root.snapGuideXActive
                x: root.snapGuideX
                width: 2
                height: parent.height
                color: Colours.palette.m3primary
                z: 10
            }

            Rectangle {
                visible: root.snapGuideYActive
                y: root.snapGuideY
                height: 2
                width: parent.width
                color: Colours.palette.m3primary
                z: 10
            }

            // Monitor Representations (Bounding Boxes)
            Repeater {
                model: root.monitorsData

                delegate: StyledRect {
                    id: monitorBox

                    required property var modelData
                    required property int index

                    readonly property real scaleFactor: root.getScaleFactor(canvasBox.width, canvasBox.height)
                    readonly property var bounds: root.getBounds()
                    readonly property real logicalW: root.calculateLogicalW(modelData)
                    readonly property real logicalH: root.calculateLogicalH(modelData)
                    readonly property bool isSelected: index === root.selectedIndex

                    x: root.getCanvasX(modelData.x || 0, scaleFactor, bounds.minX, canvasBox.width, bounds.totalW)
                    y: root.getCanvasY(modelData.y || 0, scaleFactor, bounds.minY, canvasBox.height, bounds.totalH)
                    width: Math.max(logicalW * scaleFactor, 60)
                    height: Math.max(logicalH * scaleFactor, 40)

                    radius: Tokens.rounding.medium
                    color: isSelected ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainerHigh
                    border.width: isSelected ? 2 : 1
                    border.color: isSelected ? Colours.palette.m3primary : Colours.palette.m3outline
                    opacity: modelData.disabled ? 0.4 : 1.0

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - 12
                        spacing: 2

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 4

                            MaterialIcon {
                                text: modelData.name.startsWith("eDP-") ? "laptop" : "desktop_windows"
                                fontStyle: Tokens.font.icon.small
                                color: monitorBox.isSelected ? Colours.palette.m3primary : Colours.palette.m3onSurface
                            }
                            StyledText {
                                text: modelData.name
                                font: Tokens.font.title.small
                                color: monitorBox.isSelected ? Colours.palette.m3primary : Colours.palette.m3onSurface
                                elide: Text.ElideRight
                            }
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: `${modelData.width}×${modelData.height} @ ${Math.round(modelData.scale * 100)}%`
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: `(${modelData.x}, ${modelData.y})`
                            font: Tokens.font.label.small
                            color: Colours.palette.m3primary
                        }
                    }

                    CustomMouseArea {
                        anchors.fill: parent

                        property real pressMouseX: 0
                        property real pressMouseY: 0
                        property real startLogicalX: 0
                        property real startLogicalY: 0

                        onPressed: mouse => {
                            root.selectedIndex = index;
                            pressMouseX = mouse.x;
                            pressMouseY = mouse.y;
                            startLogicalX = modelData.x || 0;
                            startLogicalY = modelData.y || 0;
                        }

                        onPositionChanged: mouse => {
                            if (mouse.buttons !== Qt.LeftButton) return;

                            const dLogicalX = (mouse.x - pressMouseX) / monitorBox.scaleFactor;
                            const dLogicalY = (mouse.y - pressMouseY) / monitorBox.scaleFactor;

                            let candX = startLogicalX + dLogicalX;
                            let candY = startLogicalY + dLogicalY;

                            const candW = monitorBox.logicalW;
                            const candH = monitorBox.logicalH;
                            const snapThreshold = 20; // logical pixels

                            let snappedX = false;
                            let snappedY = false;

                            for (let i = 0; i < root.monitorsData.length; i++) {
                                if (i === index) continue;
                                const o = root.monitorsData[i];
                                if (o.disabled) continue;

                                const oW = root.calculateLogicalW(o);
                                const oH = root.calculateLogicalH(o);

                                // Snap Horizontal Alignments
                                if (Math.abs(candX - (o.x + oW)) < snapThreshold) {
                                    candX = o.x + oW;
                                    root.snapGuideX = root.getCanvasX(candX, monitorBox.scaleFactor, monitorBox.bounds.minX, canvasBox.width, monitorBox.bounds.totalW);
                                    snappedX = true;
                                } else if (Math.abs((candX + candW) - o.x) < snapThreshold) {
                                    candX = o.x - candW;
                                    root.snapGuideX = root.getCanvasX(o.x, monitorBox.scaleFactor, monitorBox.bounds.minX, canvasBox.width, monitorBox.bounds.totalW);
                                    snappedX = true;
                                } else if (Math.abs(candX - o.x) < snapThreshold) {
                                    candX = o.x;
                                    root.snapGuideX = root.getCanvasX(o.x, monitorBox.scaleFactor, monitorBox.bounds.minX, canvasBox.width, monitorBox.bounds.totalW);
                                    snappedX = true;
                                } else if (Math.abs((candX + candW) - (o.x + oW)) < snapThreshold) {
                                    candX = o.x + oW - candW;
                                    root.snapGuideX = root.getCanvasX(o.x + oW, monitorBox.scaleFactor, monitorBox.bounds.minX, canvasBox.width, monitorBox.bounds.totalW);
                                    snappedX = true;
                                }

                                // Snap Vertical Alignments
                                if (Math.abs(candY - (o.y + oH)) < snapThreshold) {
                                    candY = o.y + oH;
                                    root.snapGuideY = root.getCanvasY(candY, monitorBox.scaleFactor, monitorBox.bounds.minY, canvasBox.height, monitorBox.bounds.totalH);
                                    snappedY = true;
                                } else if (Math.abs((candY + candH) - o.y) < snapThreshold) {
                                    candY = o.y - candH;
                                    root.snapGuideY = root.getCanvasY(o.y, monitorBox.scaleFactor, monitorBox.bounds.minY, canvasBox.height, monitorBox.bounds.totalH);
                                    snappedY = true;
                                } else if (Math.abs(candY - o.y) < snapThreshold) {
                                    candY = o.y;
                                    root.snapGuideY = root.getCanvasY(o.y, monitorBox.scaleFactor, monitorBox.bounds.minY, canvasBox.height, monitorBox.bounds.totalH);
                                    snappedY = true;
                                } else if (Math.abs((candY + candH) - (o.y + oH)) < snapThreshold) {
                                    candY = o.y + oH - candH;
                                    root.snapGuideY = root.getCanvasY(o.y + oH, monitorBox.scaleFactor, monitorBox.bounds.minY, canvasBox.height, monitorBox.bounds.totalH);
                                    snappedY = true;
                                }
                            }

                            root.snapGuideXActive = snappedX;
                            root.snapGuideYActive = snappedY;

                            const listCopy = [...root.monitorsData];
                            listCopy[index] = Object.assign({}, listCopy[index], {
                                x: Math.round(candX),
                                y: Math.round(candY)
                            });
                            root.monitorsData = listCopy;
                        }

                        onReleased: {
                            root.snapGuideXActive = false;
                            root.snapGuideYActive = false;
                        }
                    }
                }
            }
        }

        // Section 2: Precise Spatial Offsets & Screen Settings
        SectionHeader { text: qsTr("Explicit Coordinate & Scale Settings") }

        StepperRow {
            Layout.fillWidth: true
            first: true
            label: qsTr("X Offset (px)")
            subtext: qsTr("Horizontal pixel offset on workspace grid")
            from: -7680
            to: 15360
            stepSize: 10
            value: root.selectedMonitor?.x ?? 0
            onMoved: v => {
                if (root.selectedIndex >= 0 && root.selectedIndex < root.monitorsData.length) {
                    const listCopy = [...root.monitorsData];
                    listCopy[root.selectedIndex] = Object.assign({}, listCopy[root.selectedIndex], { x: Math.round(v) });
                    root.monitorsData = listCopy;
                }
            }
        }

        StepperRow {
            Layout.fillWidth: true
            label: qsTr("Y Offset (px)")
            subtext: qsTr("Vertical pixel offset on workspace grid")
            from: -4320
            to: 8640
            stepSize: 10
            value: root.selectedMonitor?.y ?? 0
            onMoved: v => {
                if (root.selectedIndex >= 0 && root.selectedIndex < root.monitorsData.length) {
                    const listCopy = [...root.monitorsData];
                    listCopy[root.selectedIndex] = Object.assign({}, listCopy[root.selectedIndex], { y: Math.round(v) });
                    root.monitorsData = listCopy;
                }
            }
        }

        SelectRow {
            Layout.fillWidth: true
            label: qsTr("Scale Factor")
            subtext: qsTr("Interface scaling for selected display")
            menuItems: root.scaleItems
            active: root.selectedMonitor ? root.scaleItems[Math.max(0, [1, 1.25, 1.5, 1.75, 2].indexOf(root.selectedMonitor.scale))] ?? null : null
            fallbackText: `${Math.round((root.selectedMonitor?.scale ?? 1) * 100)}%`
            fallbackIcon: "zoom_in"
            onSelected: item => {
                const values = [1, 1.25, 1.5, 1.75, 2];
                const newScale = values[root.scaleItems.indexOf(item)] ?? 1;
                if (root.selectedIndex >= 0 && root.selectedIndex < root.monitorsData.length) {
                    const listCopy = [...root.monitorsData];
                    listCopy[root.selectedIndex] = Object.assign({}, listCopy[root.selectedIndex], { scale: newScale });
                    root.monitorsData = listCopy;
                }
            }
        }

        SelectRow {
            Layout.fillWidth: true
            last: true
            label: qsTr("Orientation")
            subtext: qsTr("Rotation angle for selected display")
            menuItems: root.orientationItems
            active: root.selectedMonitor ? root.orientationItems[Math.max(0, Math.min(root.selectedMonitor.transform ?? 0, 3))] ?? null : null
            fallbackText: root.orientationItems[Math.max(0, Math.min(root.selectedMonitor?.transform ?? 0, 3))].text
            fallbackIcon: "screen_rotation"
            onSelected: item => {
                const newTransform = root.orientationItems.indexOf(item);
                if (root.selectedIndex >= 0 && root.selectedIndex < root.monitorsData.length) {
                    const listCopy = [...root.monitorsData];
                    listCopy[root.selectedIndex] = Object.assign({}, listCopy[root.selectedIndex], { transform: newTransform });
                    root.monitorsData = listCopy;
                }
            }
        }

        // Section 3: Spatial Layout Profiles
        SectionHeader { text: qsTr("Spatial Layout Profiles") }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: profileContent.implicitHeight + profileContent.anchors.margins * 2

            ColumnLayout {
                id: profileContent

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledTextField {
                        id: profileInput

                        Layout.fillWidth: true
                        placeholderText: qsTr("Enter profile name (e.g. Desk Setup)")
                        text: root.newProfileName
                        onTextChanged: root.newProfileName = text
                    }

                    TextButton {
                        text: qsTr("Save Profile")
                        onClicked: root.saveCurrentProfile()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.profilesList.length > 0
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: qsTr("Saved Presets:")
                        font: Tokens.font.label.medium
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    Repeater {
                        model: root.profilesList

                        delegate: TextButton {
                            required property string modelData

                            text: modelData
                            onClicked: root.applyProfile(modelData)
                        }
                    }
                }
            }
        }

        // Section 4: Apply & Confirmation Rollback Status Bar
        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: actionLayout.implicitHeight + actionLayout.anchors.margins * 2

            RowLayout {
                id: actionLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.fillWidth: true
                    text: root.statusMessage || qsTr("Apply new spatial layout to activate 20-second test preview")
                    color: root.statusIsError ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.Wrap
                }

                TextButton {
                    visible: root.pendingToken === ""
                    text: qsTr("Apply Layout")
                    onClicked: root.applyLayout()
                }

                TextButton {
                    visible: root.pendingToken !== ""
                    text: qsTr("Keep Layout")
                    onClicked: confirmProc.exec(["caelestia-display", "confirm", root.pendingToken])
                }

                TextButton {
                    visible: root.pendingToken !== ""
                    text: qsTr("Revert")
                    onClicked: rollbackProc.exec(["caelestia-display", "rollback", root.pendingToken])
                }
            }
        }
    }
}
