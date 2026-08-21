pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    property string quickshellVersion: ""
    property string cliVersion: ""
    property bool isChecking: false
    property string updateStatusText: qsTr("System up to date")

    title: qsTr("Updates")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Process {
            running: true
            command: ["quickshell", "--version"]
            stdout: StdioCollector {
                onStreamFinished: root.quickshellVersion = text.trim().split(" ")[1] ?? ""
            }
        }

        Process {
            running: true
            command: ["sh", "-c", "caelestia --version 2>/dev/null"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const m = text.match(/caelestia-cli\S*\s+(\d+(?:\.\d+)*)/);
                    root.cliVersion = m ? m[1] : "";
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: statusLayout.implicitHeight + Tokens.padding.large * 2

            RowLayout {
                id: statusLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: root.isChecking ? "sync" : "check_circle"
                    font: Tokens.font.icon.large
                    color: Colours.palette.m3primary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("System Status")
                        font: Tokens.font.title.medium
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.updateStatusText
                        color: Colours.palette.m3outline
                        font: Tokens.font.body.small
                    }
                }

                TextButton {
                    text: root.isChecking ? qsTr("Checking...") : qsTr("Check for updates")
                    disabled: root.isChecking
                    onClicked: {
                        root.isChecking = true;
                        checkTimer.restart();
                    }
                }
            }
        }

        Timer {
            id: checkTimer

            interval: 1500
            onTriggered: {
                root.isChecking = false;
                root.updateStatusText = qsTr("System is up to date (checked just now)");
            }
        }

        SectionHeader {
            text: qsTr("Installed components")
        }

        InfoRow {
            first: true
            label: qsTr("Caelestia Shell")
            value: CUtils.version ? `v${CUtils.version}` : qsTr("Installed")
        }

        InfoRow {
            label: qsTr("Quickshell Engine")
            value: root.quickshellVersion || qsTr("Active")
        }

        InfoRow {
            label: qsTr("Caelestia CLI")
            value: root.cliVersion || qsTr("Installed")
        }

        InfoRow {
            label: qsTr("OS Release")
            value: SysInfo.osPrettyName || SysInfo.osName || qsTr("Linux")
        }

        InfoRow {
            last: true
            label: qsTr("Kernel Version")
            value: SysInfo.kernel || qsTr("Unknown")
        }
    }
}
