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

    title: qsTr("Display")

    property var monitorList: Hypr.monitors.values
    property bool showConfirmSave: false
    property string errorMessage: ""

    Process {
        id: monitorProc
        onExited: exitCode => { // qmllint disable signal-handler-parameters
            if (exitCode !== 0) {
                root.errorMessage = qsTr("Process failed. Please check your configuration.");
            } else {
                root.errorMessage = "";
            }
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        StyledText {
            Layout.fillWidth: true
            text: root.errorMessage
            color: Colours.palette.m3error
            font: Tokens.font.body.small
            visible: root.errorMessage !== ""
            wrapMode: Text.Wrap
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: false
            implicitHeight: 300

            Item {
                id: canvas
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium

                property real minX: 0
                property real minY: 0
                property real maxX: 1920
                property real maxY: 1080
                
                property real sFactor: 0.1
                property real offsetX: 0
                property real offsetY: 0

                function updateBounds() {
                    let mx = 0, my = 0, mX = 1920, mY = 1080;
                    if (root.monitorList.length > 0) {
                        mx = root.monitorList[0].x;
                        my = root.monitorList[0].y;
                        mX = root.monitorList[0].x + root.monitorList[0].width;
                        mY = root.monitorList[0].y + root.monitorList[0].height;
                        for (let i = 1; i < root.monitorList.length; i++) {
                            const m = root.monitorList[i];
                            mx = Math.min(mx, m.x);
                            my = Math.min(my, m.y);
                            mX = Math.max(mX, m.x + m.width);
                            mY = Math.max(mY, m.y + m.height);
                        }
                    }
                    minX = mx;
                    minY = my;
                    maxX = mX;
                    maxY = mY;
                    
                    let cw = canvas.width || 100;
                    let ch = canvas.height || 100;
                    let w = maxX - minX || 1920;
                    let h = maxY - minY || 1080;
                    
                    sFactor = Math.min(cw / w, ch / h) * 0.8;
                    offsetX = (cw - w * sFactor) / 2;
                    offsetY = (ch - h * sFactor) / 2;
                }

                Component.onCompleted: updateBounds()
                onWidthChanged: updateBounds()
                onHeightChanged: updateBounds()

                Connections {
                    target: Hypr
                    function onMonitorsChanged(): void {
                        canvas.updateBounds();
                    }
                }

                Repeater {
                    model: root.monitorList
                    delegate: Rectangle {
                        id: monRect
                        required property var modelData

                        x: (modelData.x - canvas.minX) * canvas.sFactor + canvas.offsetX
                        y: (modelData.y - canvas.minY) * canvas.sFactor + canvas.offsetY
                        width: modelData.width * canvas.sFactor
                        height: modelData.height * canvas.sFactor
                        
                        color: Colours.palette.m3primaryContainer
                        border.color: Colours.palette.m3primary
                        border.width: 2
                        radius: Tokens.rounding.medium

                        StyledText {
                            anchors.centerIn: parent
                            text: monRect.modelData.name
                            font: Tokens.font.body.medium
                            color: Colours.palette.m3onPrimaryContainer
                        }

                        MouseArea {
                            id: dragArea
                            anchors.fill: parent
                            drag.target: monRect
                            drag.axis: Drag.XAndYAxis
                            
                            onReleased: {
                                let newPx = Math.round((monRect.x - canvas.offsetX) / canvas.sFactor + canvas.minX);
                                let newPy = Math.round((monRect.y - canvas.offsetY) / canvas.sFactor + canvas.minY);
                                
                                // Snap to nearest 10 pixels to avoid weird tiny offsets
                                newPx = Math.round(newPx / 10) * 10;
                                newPy = Math.round(newPy / 10) * 10;
                                
                                let m = monRect.modelData;
                                let res = `${m.width}x${m.height}@${m.refreshRate}`;
                                
                                monitorProc.exec([
                                    Quickshell.shellPath("modules/nexus/scripts/manage_monitors.py"),
                                    "--apply",
                                    "--name", m.name,
                                    "--res", res,
                                    "--pos", `${newPx}x${newPy}`,
                                    "--scale", String(m.scale),
                                    "--old-res", res,
                                    "--old-pos", `${m.x}x${m.y}`,
                                    "--old-scale", String(m.scale)
                                ]);
                                
                                Qt.callLater(() => { canvas.updateBounds(); });
                            }
                        }
                    }
                }
            }
        }

        Repeater {
            model: root.monitorList
            delegate: ConnectedRect {
                id: monitorRect
                Layout.fillWidth: true
                first: false
                last: false
                implicitHeight: col.implicitHeight + col.anchors.margins * 2

                required property var modelData

                ColumnLayout {
                    id: col
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    StyledText {
                        Layout.fillWidth: true
                        text: parent.modelData.name + " (" + parent.modelData.description + ")"
                        font: Tokens.font.title.small
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        StyledText {
                            text: qsTr("Scale:")
                            font: Tokens.font.body.small
                        }

                        Repeater {
                            model: [1, 1.25, 1.5, 2]
                            delegate: TextButton {
                                text: modelData + "x"
                                onClicked: {
                                    let m = monitorRect.modelData;
                                    let res = `${m.width}x${m.height}@${m.refreshRate}`;
                                    
                                    monitorProc.exec([
                                        Quickshell.shellPath("modules/nexus/scripts/manage_monitors.py"),
                                        "--apply",
                                        "--name", m.name,
                                        "--res", res,
                                        "--pos", `${m.x}x${m.y}`,
                                        "--scale", String(modelData),
                                        "--old-res", res,
                                        "--old-pos", `${m.x}x${m.y}`,
                                        "--old-scale", String(m.scale)
                                    ]);
                                }
                            }
                        }
                    }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: false
            last: true
            implicitHeight: saveCol.implicitHeight + saveCol.anchors.margins * 2

            ColumnLayout {
                id: saveCol
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    StyledText {
                        Layout.fillWidth: true
                        text: root.showConfirmSave ? qsTr("Apply to hyprland.conf and persist changes?") : qsTr("Save Display Settings")
                        font: Tokens.font.body.small
                    }

                    TextButton {
                        text: root.showConfirmSave ? qsTr("Cancel") : ""
                        visible: root.showConfirmSave
                        onClicked: {
                            root.showConfirmSave = false;
                        }
                    }

                    TextButton {
                        text: root.showConfirmSave ? qsTr("Yes") : qsTr("Save")
                        onClicked: {
                            if (!root.showConfirmSave) {
                                root.showConfirmSave = true;
                            } else {
                                let monitorsData = root.monitorList.map(m => ({
                                    name: m.name,
                                    res: `${m.width}x${m.height}@${m.refreshRate}`,
                                    pos: `${m.x}x${m.y}`,
                                    scale: m.scale
                                }));
                                monitorProc.exec([Quickshell.shellPath("modules/nexus/scripts/manage_monitors.py"), "--save", "--monitors-json", JSON.stringify(monitorsData)]);
                                root.showConfirmSave = false;
                            }
                        }
                    }
                }
            }
        }
    }
}
