pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Windows")

    property bool focusFollowsMouse: false
    property bool naturalWorkspaceScroll: true
    property int gapsIn: 5
    property int gapsOut: 10
    property int rounding: 15
    property real windowOpacity: 0.95
    property string statusMessage: ""
    property bool statusIsError: false

    function dispatch(request: string): void {
        Hypr.dispatch(request);
    }

    function keyword(name: string, value: string): void {
        Hypr.extras.batchMessage([`keyword ${name} ${value}`]);
    }

    function saveSettings(): void {
        const begin = "# BEGIN CAELESTIA WINDOW SETTINGS";
        const end = "# END CAELESTIA WINDOW SETTINGS";
        const block = `${begin}\ninput {\n    follow_mouse = ${focusFollowsMouse ? 1 : 0}\n}\nbinds {\n    workspace_back_and_forth = ${naturalWorkspaceScroll ? 1 : 0}\n}\ngeneral {\n    gaps_in = ${gapsIn}\n    gaps_out = ${gapsOut}\n}\ndecoration {\n    rounding = ${rounding}\n    active_opacity = ${windowOpacity}\n    inactive_opacity = ${windowOpacity}\n}\n${end}`;
        const current = hyprUserFile.text();
        const start = current.indexOf(begin);
        const finish = current.indexOf(end);
        let preserved = current;
        if (start >= 0 && finish >= start)
            preserved = current.slice(0, start) + current.slice(finish + end.length);
        hyprUserFile.setText(`${preserved.trimEnd()}\n\n${block}\n`);

        keyword("input:follow_mouse", focusFollowsMouse ? "1" : "0");
        keyword("binds:workspace_back_and_forth", naturalWorkspaceScroll ? "1" : "0");
        keyword("general:gaps_in", String(gapsIn));
        keyword("general:gaps_out", String(gapsOut));
        keyword("decoration:rounding", String(rounding));
        keyword("decoration:active_opacity", String(windowOpacity));
        keyword("decoration:inactive_opacity", String(windowOpacity));
        root.statusMessage = qsTr("Window settings saved and applied");
        root.statusIsError = false;
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        FileView {
            id: hyprUserFile

            path: `${Paths.config}/hypr-user.conf`
            printErrors: true
        }

        SectionHeader {
            first: true
            text: qsTr("Active window")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: false
            implicitHeight: activeWindowRow.implicitHeight + activeWindowRow.anchors.margins * 2

            RowLayout {
                id: activeWindowRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: Icons.getAppCategoryIcon(Hypr.activeToplevel?.lastIpcObject.class, "desktop_windows")
                    color: Colours.palette.m3primary
                    font: Tokens.font.icon.large
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: Hypr.activeToplevel?.title ?? qsTr("No active window")
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Strings.friendlyAppName(Hypr.activeToplevel?.lastIpcObject.class) || qsTr("Focus a window to use these actions")
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            last: true
            implicitHeight: actionGrid.implicitHeight + actionGrid.anchors.margins * 2

            GridLayout {
                id: actionGrid

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                columns: width > 560 ? 4 : 2
                rowSpacing: Tokens.spacing.small
                columnSpacing: Tokens.spacing.small

                IconTextButton {
                    Layout.fillWidth: true
                    icon: "center_focus_strong"
                    text: qsTr("Center")
                    onClicked: root.dispatch("centerwindow 1")
                }

                IconTextButton {
                    Layout.fillWidth: true
                    icon: "open_in_full"
                    text: qsTr("Resize")
                    onClicked: {
                        root.dispatch("resizeactive exact 55% 70%");
                        root.dispatch("centerwindow 1");
                    }
                }

                IconTextButton {
                    Layout.fillWidth: true
                    icon: "picture_in_picture"
                    text: qsTr("PiP")
                    onClicked: Quickshell.execDetached(["caelestia", "resizer", "pip"])
                }

                IconTextButton {
                    Layout.fillWidth: true
                    icon: "push_pin"
                    text: qsTr("Pin")
                    onClicked: root.dispatch("pin")
                }

                IconTextButton {
                    Layout.fillWidth: true
                    icon: "fullscreen"
                    text: qsTr("Fullscreen")
                    onClicked: root.dispatch("fullscreen 0")
                }

                IconTextButton {
                    Layout.fillWidth: true
                    icon: "select_window"
                    text: qsTr("Float")
                    onClicked: Quickshell.execDetached([`${Quickshell.env("HOME")}/.config/hypr/scripts/toggle-floating-preserve-position.sh`])
                }

                IconTextButton {
                    Layout.fillWidth: true
                    icon: "stack"
                    text: qsTr("Group")
                    onClicked: root.dispatch("togglegroup")
                }

                IconTextButton {
                    Layout.fillWidth: true
                    icon: "move_group"
                    text: qsTr("Special")
                    onClicked: root.dispatch("movetoworkspace special:special")
                }
            }
        }

        SectionHeader {
            text: qsTr("Behaviour")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Focus follows mouse")
            subtext: qsTr("Move focus when the pointer enters a window")
            checked: root.focusFollowsMouse
            onToggled: {
                root.focusFollowsMouse = checked;
                root.keyword("input:follow_mouse", checked ? "1" : "0");
            }
        }

        ToggleRow {
            Layout.fillWidth: true
            last: true
            text: qsTr("Workspace back and forth")
            subtext: qsTr("Switching to the current workspace returns to the last one")
            checked: root.naturalWorkspaceScroll
            onToggled: {
                root.naturalWorkspaceScroll = checked;
                root.keyword("binds:workspace_back_and_forth", checked ? "1" : "0");
            }
        }

        SectionHeader {
            text: qsTr("Appearance")
        }

        StepperRow {
            Layout.fillWidth: true
            first: true
            label: qsTr("Inner gaps")
            subtext: qsTr("Space between tiled windows")
            value: root.gapsIn
            from: 0
            to: 50
            stepSize: 1
            onMoved: v => {
                root.gapsIn = v;
                root.keyword("general:gaps_in", String(v));
            }
        }

        StepperRow {
            Layout.fillWidth: true
            label: qsTr("Outer gaps")
            subtext: qsTr("Space around workspaces")
            value: root.gapsOut
            from: 0
            to: 80
            stepSize: 1
            onMoved: v => {
                root.gapsOut = v;
                root.keyword("general:gaps_out", String(v));
            }
        }

        StepperRow {
            Layout.fillWidth: true
            label: qsTr("Corner radius")
            subtext: qsTr("Window rounding")
            value: root.rounding
            from: 0
            to: 40
            stepSize: 1
            onMoved: v => {
                root.rounding = v;
                root.keyword("decoration:rounding", String(v));
            }
        }

        StepperRow {
            Layout.fillWidth: true
            last: true
            label: qsTr("Opacity")
            subtext: qsTr("Active and inactive window opacity")
            value: Math.round(root.windowOpacity * 100)
            from: 50
            to: 100
            stepSize: 5
            onMoved: v => {
                root.windowOpacity = v / 100;
                root.keyword("decoration:active_opacity", String(root.windowOpacity));
                root.keyword("decoration:inactive_opacity", String(root.windowOpacity));
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: saveRow.implicitHeight + saveRow.anchors.margins * 2

            RowLayout {
                id: saveRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.fillWidth: true
                    text: root.statusMessage || qsTr("Runtime changes can be saved to a managed Hyprland config")
                    color: root.statusIsError ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.Wrap
                }

                TextButton {
                    text: qsTr("Save")
                    onClicked: root.saveSettings()
                }
            }
        }
    }
}
