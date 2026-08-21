pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Taskbar")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Behaviour
        SectionHeader {
            first: true
            text: qsTr("Behaviour & Position")
        }

        SelectRow {
            Layout.fillWidth: true
            first: true
            label: qsTr("Position")
            subtext: qsTr("Screen edge where the status bar is placed")
            active: {
                switch (GlobalConfig.bar.edge) {
                case "top": return itemTop;
                case "bottom": return itemBottom;
                case "right": return itemRight;
                case "left":
                default: return itemLeft;
                }
            }
            menuItems: [
                MenuItem {
                    id: itemLeft

                    text: qsTr("Left")
                    onTriggered: GlobalConfig.bar.edge = "left"
                },
                MenuItem {
                    id: itemTop

                    text: qsTr("Top")
                    onTriggered: GlobalConfig.bar.edge = "top"
                },
                MenuItem {
                    id: itemRight

                    text: qsTr("Right")
                    onTriggered: GlobalConfig.bar.edge = "right"
                },
                MenuItem {
                    id: itemBottom

                    text: qsTr("Bottom")
                    onTriggered: GlobalConfig.bar.edge = "bottom"
                }
            ]
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Persistent")
            subtext: qsTr("Keep the bar visible at all times")
            checked: GlobalConfig.bar.persistent
            onToggled: GlobalConfig.bar.persistent = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Show on hover")
            subtext: qsTr("Reveal the bar when the cursor reaches the screen edge")
            checked: GlobalConfig.bar.showOnHover
            onToggled: GlobalConfig.bar.showOnHover = checked
        }

        StepperRow {
            Layout.fillWidth: true
            last: true
            label: qsTr("Drag threshold")
            subtext: qsTr("Pixels dragged before the bar reveals")
            value: GlobalConfig.bar.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.bar.dragThreshold = v
        }

        // Module arrangement
        SectionHeader {
            text: qsTr("Module arrangement")
        }

        Repeater {
            model: GlobalConfig.bar.entries

            delegate: ConnectedRect {
                required property int index
                required property var modelData

                readonly property string entryId: modelData.id || ""
                readonly property bool entryEnabled: modelData.enabled !== false

                readonly property string entryName: {
                    switch (entryId) {
                    case "logo": return qsTr("Logo");
                    case "workspaces": return qsTr("Workspaces");
                    case "spacer": return qsTr("Spacer");
                    case "activeWindow": return qsTr("Active window");
                    case "tray": return qsTr("Tray");
                    case "clock": return qsTr("Clock");
                    case "statusIcons": return qsTr("Status icons");
                    case "power": return qsTr("Power");
                    default: return entryId;
                    }
                }

                readonly property string entryIcon: {
                    switch (entryId) {
                    case "logo": return "home";
                    case "workspaces": return "workspaces";
                    case "spacer": return "space_bar";
                    case "activeWindow": return "web_asset";
                    case "tray": return "widgets";
                    case "clock": return "schedule";
                    case "statusIcons": return "signal_cellular_alt";
                    case "power": return "power_settings_new";
                    default: return "extension";
                    }
                }

                Layout.fillWidth: true
                first: index === 0
                last: index === GlobalConfig.bar.entries.length - 1
                implicitHeight: entryRow.implicitHeight + entryRow.anchors.margins * 2

                RowLayout {
                    id: entryRow

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: parent.parent.entryIcon
                        font: Tokens.font.icon.medium
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: parent.parent.entryName
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    IconButton {
                        icon: "arrow_upward"
                        disabled: index === 0
                        onClicked: {
                            let list = [];
                            for (let i = 0; i < GlobalConfig.bar.entries.length; i++) {
                                list.push(Object.assign({}, GlobalConfig.bar.entries[i]));
                            }
                            let temp = list[index - 1];
                            list[index - 1] = list[index];
                            list[index] = temp;
                            GlobalConfig.bar.entries = list;
                        }
                    }

                    IconButton {
                        icon: "arrow_downward"
                        disabled: index === GlobalConfig.bar.entries.length - 1
                        onClicked: {
                            let list = [];
                            for (let i = 0; i < GlobalConfig.bar.entries.length; i++) {
                                list.push(Object.assign({}, GlobalConfig.bar.entries[i]));
                            }
                            let temp = list[index + 1];
                            list[index + 1] = list[index];
                            list[index] = temp;
                            GlobalConfig.bar.entries = list;
                        }
                    }

                    StyledSwitch {
                        checked: parent.parent.entryEnabled
                        onToggled: {
                            let list = [];
                            for (let i = 0; i < GlobalConfig.bar.entries.length; i++) {
                                list.push(Object.assign({}, GlobalConfig.bar.entries[i]));
                            }
                            list[index].enabled = checked;
                            GlobalConfig.bar.entries = list;
                        }
                    }
                }
            }
        }

        // Components
        SectionHeader {
            text: qsTr("Components")
        }

        NavRow {
            first: true
            icon: "workspaces"
            label: qsTr("Workspaces")
            status: qsTr("Indicators, window icons")
            onClicked: root.nState.openSubPage(5)
        }

        NavRow {
            icon: "web_asset"
            label: qsTr("Active window")
            status: qsTr("Title display, popout")
            onClicked: root.nState.openSubPage(6)
        }

        NavRow {
            icon: "widgets"
            label: qsTr("Tray")
            status: qsTr("System tray icons")
            onClicked: root.nState.openSubPage(7)
        }

        NavRow {
            icon: "signal_cellular_alt"
            label: qsTr("Status icons")
            status: qsTr("Visible indicators")
            onClicked: root.nState.openSubPage(8)
        }

        NavRow {
            last: true
            icon: "schedule"
            label: qsTr("Clock")
            status: qsTr("Date, icon, background")
            onClicked: root.nState.openSubPage(9)
        }

        // Scroll actions
        SectionHeader {
            text: qsTr("Scroll actions")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Workspaces")
            subtext: qsTr("Scroll over the workspace indicator to switch workspaces")
            checked: GlobalConfig.bar.scrollActions.workspaces
            onToggled: GlobalConfig.bar.scrollActions.workspaces = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Volume")
            subtext: qsTr("Scroll on the top half of the bar to adjust volume")
            checked: GlobalConfig.bar.scrollActions.volume
            onToggled: GlobalConfig.bar.scrollActions.volume = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            last: true
            text: qsTr("Brightness")
            subtext: qsTr("Scroll on the bottom half of the bar to adjust brightness")
            checked: GlobalConfig.bar.scrollActions.brightness
            onToggled: GlobalConfig.bar.scrollActions.brightness = checked
        }
    }
}
