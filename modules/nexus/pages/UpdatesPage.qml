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
    property bool hasError: false
    property string updateStatusText: qsTr("System up to date")

    title: qsTr("Updates")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Process {
            id: updateCheckProcess

            running: false
            command: [
                "sh", "-c",
                "found=0; updates=0; " +
                "if command -v checkupdates >/dev/null 2>&1; then found=1; count=$(checkupdates 2>/dev/null | wc -l); updates=$((updates + count)); fi; " +
                "if command -v flatpak >/dev/null 2>&1; then found=1; count=$(flatpak remote-ls --updates 2>/dev/null | wc -l); updates=$((updates + count)); fi; " +
                "if command -v apt-get >/dev/null 2>&1; then found=1; count=$(apt-get -s upgrade 2>/dev/null | grep -E '^Inst ' | wc -l); updates=$((updates + count)); fi; " +
                "if command -v dnf >/dev/null 2>&1; then found=1; count=$(dnf check-update --q 2>/dev/null | grep -v '^$' | wc -l); updates=$((updates + count)); fi; " +
                "if [ $found -eq 0 ]; then echo 'UNAVAILABLE'; else echo \"UPDATES:$updates\"; fi"
            ]

            stdout: StdioCollector {
                onStreamFinished: {
                    root.isChecking = false;
                    const output = text.trim();
                    if (output.startsWith("UPDATES:")) {
                        const count = parseInt(output.substring(8), 10) || 0;
                        root.hasError = false;
                        if (count === 0) {
                            root.updateStatusText = qsTr("System is up to date (checked just now)");
                        } else {
                            root.updateStatusText = qsTr("%1 update(s) available").arg(count);
                        }
                    } else if (output === "UNAVAILABLE") {
                        root.hasError = true;
                        root.updateStatusText = qsTr("Package update checking unavailable (no supported package manager found)");
                    } else {
                        root.hasError = true;
                        root.updateStatusText = qsTr("Update check returned invalid status");
                    }
                }
            }

            onExited: (exitCode, exitStatus) => {
                root.isChecking = false;
                if (exitCode !== 0 && exitCode !== 100) {
                    root.hasError = true;
                    root.updateStatusText = qsTr("Update check failed (exit code %1)").arg(exitCode);
                }
            }
        }

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
                    text: root.isChecking ? "sync" : root.hasError ? "error" : "check_circle"
                    font: Tokens.font.icon.large
                    color: root.isChecking ? Colours.palette.m3primary : root.hasError ? Colours.palette.m3error : Colours.palette.m3primary
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
                        root.hasError = false;
                        root.updateStatusText = qsTr("Querying package repositories...");
                        updateCheckProcess.running = true;
                    }
                }
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
