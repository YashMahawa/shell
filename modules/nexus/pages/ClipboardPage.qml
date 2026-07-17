pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Clipboard")
    property int retentionDays: 7
    property string statusMessage: ""

    function refresh(): void {
        if (!statusProc.running)
            statusProc.exec(["caelestia-clipboard", "retention-status"]);
    }

    function setRetention(days: int): void {
        if (manager.running)
            return;
        root.retentionDays = days;
        manager.exec(["caelestia-clipboard", "retention", String(days)]);
    }

    Component.onCompleted: refresh()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Process {
            id: statusProc
            stdout: StdioCollector {
                onStreamFinished: {
                    try { root.retentionDays = JSON.parse(text).retentionDays ?? 7; }
                    catch (error) { root.statusMessage = qsTr("Could not read clipboard settings"); }
                }
            }
        }

        Process {
            id: manager
            onExited: exitCode => { // qmllint disable signal-handler-parameters
                root.statusMessage = exitCode === 0 ? qsTr("Clipboard cleanup updated") : qsTr("Could not update clipboard cleanup");
                root.refresh();
            }
        }

        SectionHeader { text: qsTr("Automatic cleanup") }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.medium
            Layout.rightMargin: Tokens.padding.medium
            Layout.bottomMargin: Tokens.spacing.small
            text: qsTr("Unpinned clipboard entries are removed after this time. Pinned text and images are always preserved.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.Wrap
        }

        Repeater {
            model: [
                { "days": 1, "label": qsTr("1 day"), "detail": qsTr("Smallest history and storage use") },
                { "days": 2, "label": qsTr("2 days"), "detail": qsTr("Balanced recent clipboard history") },
                { "days": 7, "label": qsTr("1 week"), "detail": qsTr("Keep a longer working history") }
            ]

            ConnectedRect {
                id: option
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: 66
                first: index === 0
                last: index === 2
                color: root.retentionDays === modelData.days ? Colours.layer(Colours.palette.m3primaryContainer, 0.72) : Colours.tPalette.m3surfaceContainer

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.verticalCenter: parent.verticalCenter
                    StyledText { text: option.modelData.label; font: Tokens.font.body.medium }
                    StyledText { text: option.modelData.detail; color: Colours.palette.m3outline; font: Tokens.font.label.small }
                }

                MaterialIcon {
                    anchors.right: parent.right
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.retentionDays === option.modelData.days ? "check_circle" : "radio_button_unchecked"
                    color: root.retentionDays === option.modelData.days ? Colours.palette.m3primary : Colours.palette.m3outline
                    fill: root.retentionDays === option.modelData.days ? 1 : 0
                    renderType: Text.NativeRendering
                }

                StateLayer {
                    anchors.fill: parent
                    onClicked: root.setRetention(option.modelData.days)
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            visible: root.statusMessage.length > 0
            text: root.statusMessage
            color: Colours.palette.m3primary
            font: Tokens.font.body.small
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
