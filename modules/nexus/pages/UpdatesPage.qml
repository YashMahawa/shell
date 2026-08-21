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
    property bool hasChecked: false
    property bool isStale: false
    property string statusState: "not_checked"
    property string updateStatusText: qsTr("Not checked")
    property string lastCheckedTime: ""
    property list<var> backendResults: []

    title: qsTr("Updates")

    Timer {
        id: checkTimeoutTimer

        interval: 15000
        repeat: false
        onTriggered: {
            if (updateCheckProcess.running) {
                updateCheckProcess.running = false;
                root.isChecking = false;
                if (root.hasChecked) {
                    root.isStale = true;
                    root.statusState = "stale";
                    root.updateStatusText = qsTr("Stale result (re-check timed out after 15s)");
                } else {
                    root.statusState = "timeout";
                    root.hasError = true;
                    root.updateStatusText = qsTr("Update check timed out after 15s");
                }
            }
        }
    }

    Process {
        id: updateCheckProcess

        running: false
        command: [
            "sh", "-c",
            "check_backend() {\n" +
            "    name=\"$1\"\n" +
            "    cmd=\"$2\"\n" +
            "    if ! command -v \"$cmd\" >/dev/null 2>&1; then\n" +
            "        echo \"BACKEND:$name:UNAVAILABLE:0:0:Not installed\"\n" +
            "        return\n" +
            "    fi\n" +
            "    case \"$name\" in\n" +
            "        \"Arch Linux (checkupdates)\")\n" +
            "            out=$(checkupdates 2>/dev/null)\n" +
            "            ec=$?\n" +
            "            if [ $ec -eq 0 ]; then\n" +
            "                cnt=$(echo \"$out\" | grep -c .)\n" +
            "                echo \"BACKEND:$name:SUCCESS:$cnt:0:$cnt update(s) available\"\n" +
            "            elif [ $ec -eq 2 ]; then\n" +
            "                echo \"BACKEND:$name:SUCCESS:0:2:Up to date\"\n" +
            "            else\n" +
            "                echo \"BACKEND:$name:FAILED:0:$ec:Exit code $ec\"\n" +
            "            fi\n" +
            "            ;;\n" +
            "        \"Debian/Ubuntu (apt)\")\n" +
            "            out=$(apt-get -s upgrade 2>/dev/null)\n" +
            "            ec=$?\n" +
            "            if [ $ec -eq 0 ]; then\n" +
            "                cnt=$(echo \"$out\" | grep -c '^Inst ')\n" +
            "                echo \"BACKEND:$name:SUCCESS:$cnt:0:$cnt update(s) available\"\n" +
            "            else\n" +
            "                echo \"BACKEND:$name:FAILED:0:$ec:Exit code $ec\"\n" +
            "            fi\n" +
            "            ;;\n" +
            "        \"Fedora/RHEL (dnf)\")\n" +
            "            out=$(dnf check-update -q 2>/dev/null)\n" +
            "            ec=$?\n" +
            "            if [ $ec -eq 100 ]; then\n" +
            "                cnt=$(echo \"$out\" | grep -v '^$' | wc -l)\n" +
            "                echo \"BACKEND:$name:SUCCESS:$cnt:100:$cnt update(s) available\"\n" +
            "            elif [ $ec -eq 0 ]; then\n" +
            "                echo \"BACKEND:$name:SUCCESS:0:0:Up to date\"\n" +
            "            else\n" +
            "                echo \"BACKEND:$name:FAILED:0:$ec:Exit code $ec\"\n" +
            "            fi\n" +
            "            ;;\n" +
            "        \"openSUSE (zypper)\")\n" +
            "            out=$(zypper lu 2>/dev/null)\n" +
            "            ec=$?\n" +
            "            if [ $ec -eq 100 ]; then\n" +
            "                cnt=$(echo \"$out\" | grep -c '^v ')\n" +
            "                echo \"BACKEND:$name:SUCCESS:$cnt:100:$cnt update(s) available\"\n" +
            "            elif [ $ec -eq 0 ]; then\n" +
            "                echo \"BACKEND:$name:SUCCESS:0:0:Up to date\"\n" +
            "            else\n" +
            "                echo \"BACKEND:$name:FAILED:0:$ec:Exit code $ec\"\n" +
            "            fi\n" +
            "            ;;\n" +
            "        \"Flatpak Packages\")\n" +
            "            out=$(flatpak remote-ls --updates 2>/dev/null)\n" +
            "            ec=$?\n" +
            "            if [ $ec -eq 0 ]; then\n" +
            "                cnt=$(echo \"$out\" | grep -c .)\n" +
            "                echo \"BACKEND:$name:SUCCESS:$cnt:0:$cnt update(s) available\"\n" +
            "            else\n" +
            "                echo \"BACKEND:$name:FAILED:0:$ec:Exit code $ec\"\n" +
            "            fi\n" +
            "            ;;\n" +
            "    esac\n" +
            "}\n" +
            "check_backend \"Arch Linux (checkupdates)\" \"checkupdates\"\n" +
            "check_backend \"Debian/Ubuntu (apt)\" \"apt-get\"\n" +
            "check_backend \"Fedora/RHEL (dnf)\" \"dnf\"\n" +
            "check_backend \"openSUSE (zypper)\" \"zypper\"\n" +
            "check_backend \"Flatpak Packages\" \"flatpak\"\n"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                checkTimeoutTimer.stop();
                root.isChecking = false;

                let results = [];
                let detected = 0;
                let successes = 0;
                let failures = 0;
                let totalUpdates = 0;

                const lines = text.trim().split("\n");
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i].trim();
                    if (!line.startsWith("BACKEND:")) continue;
                    const parts = line.substring(8).split(":");
                    if (parts.length < 5) continue;
                    const name = parts[0];
                    const status = parts[1];
                    const count = parseInt(parts[2], 10) || 0;
                    const exitCode = parseInt(parts[3], 10) || 0;
                    const message = parts[4];

                    if (status !== "UNAVAILABLE") {
                        detected++;
                        if (status === "SUCCESS") {
                            successes++;
                            totalUpdates += count;
                        } else {
                            failures++;
                        }
                    }
                    results.push({
                        name: name,
                        status: status,
                        count: count,
                        exitCode: exitCode,
                        message: message
                    });
                }

                root.backendResults = results;
                root.hasChecked = true;
                root.isStale = false;
                const nowStr = Qt.formatTime(new Date(), "hh:mm:ss");
                root.lastCheckedTime = nowStr;

                if (detected === 0) {
                    root.statusState = "unavailable";
                    root.hasError = true;
                    root.updateStatusText = qsTr("Package update checking unavailable (no supported package manager found)");
                } else if (failures === detected) {
                    root.statusState = "failed";
                    root.hasError = true;
                    root.updateStatusText = qsTr("Update check failed across all package backends");
                } else if (failures > 0 && successes > 0) {
                    root.statusState = "partial_failure";
                    root.hasError = true;
                    root.updateStatusText = qsTr("Partial failure: %1 backend(s) succeeded, %2 failed").arg(successes).arg(failures);
                } else if (failures === 0) {
                    root.hasError = false;
                    if (totalUpdates === 0) {
                        root.statusState = "up_to_date";
                        root.updateStatusText = qsTr("System is up to date (checked at %1)").arg(nowStr);
                    } else {
                        root.statusState = "updates_available";
                        root.updateStatusText = qsTr("%1 update(s) available across %2 backend(s)").arg(totalUpdates).arg(successes);
                    }
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            checkTimeoutTimer.stop();
            if (root.isChecking) {
                root.isChecking = false;
                if (exitCode !== 0) {
                    root.hasError = true;
                    if (root.hasChecked) {
                        root.isStale = true;
                        root.statusState = "stale";
                        root.updateStatusText = qsTr("Stale result (re-check process exited with code %1)").arg(exitCode);
                    } else {
                        root.statusState = "failed";
                        root.updateStatusText = qsTr("Update check process failed (exit code %1)").arg(exitCode);
                    }
                }
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

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

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
                    text: {
                        if (root.isChecking) return "sync";
                        if (root.statusState === "not_checked") return "help_outline";
                        if (root.statusState === "up_to_date") return "check_circle";
                        if (root.statusState === "updates_available") return "download";
                        if (root.statusState === "partial_failure") return "warning";
                        if (root.statusState === "stale") return "history";
                        if (root.statusState === "timeout") return "schedule";
                        if (root.statusState === "unavailable") return "search_off";
                        return "error";
                    }
                    color: {
                        if (root.isChecking) return Colours.palette.m3primary;
                        if (root.statusState === "not_checked") return Colours.palette.m3outline;
                        if (root.statusState === "up_to_date") return Colours.palette.m3primary;
                        if (root.statusState === "updates_available") return Colours.palette.m3primary;
                        if (root.statusState === "partial_failure" || root.statusState === "stale" || root.statusState === "timeout") return Colours.palette.m3tertiary || Colours.palette.m3primary;
                        return Colours.palette.m3error;
                    }
                    font: Tokens.font.icon.large
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
                        root.statusState = "checking";
                        root.updateStatusText = qsTr("Querying package repositories...");
                        checkTimeoutTimer.restart();
                        updateCheckProcess.running = true;
                    }
                }
            }
        }

        SectionHeader {
            text: qsTr("Detected package backends")
        }

        Repeater {
            model: root.backendResults

            delegate: InfoRow {
                required property var modelData
                required property int index

                first: index === 0
                last: index === root.backendResults.length - 1
                label: modelData.name
                value: {
                    if (modelData.status === "UNAVAILABLE") return qsTr("Not installed");
                    if (modelData.status === "SUCCESS") {
                        return modelData.count > 0 ? qsTr("%1 update(s) available").arg(modelData.count) : qsTr("Up to date");
                    }
                    if (modelData.status === "FAILED") return qsTr("Failed (exit code %1)").arg(modelData.exitCode);
                    if (modelData.status === "TIMEOUT") return qsTr("Timed out");
                    return modelData.message || qsTr("Unknown");
                }
            }
        }

        InfoRow {
            visible: root.backendResults.length === 0
            first: true
            last: true
            label: qsTr("Package backends")
            value: qsTr("Not checked")
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
