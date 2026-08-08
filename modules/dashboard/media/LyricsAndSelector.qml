import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property bool active
    property bool toolsOpen: false
    property bool retained: false

    function syncRetention(): void {
        if (active && !retained) {
            SyllableLyrics.retain();
            retained = true;
        } else if (!active && retained) {
            SyllableLyrics.release();
            retained = false;
        }
    }

    onActiveChanged: syncRetention()
    Component.onCompleted: syncRetention()
    Component.onDestruction: {
        if (retained)
            SyllableLyrics.release();
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        spacing: Tokens.spacing.small

        RowLayout {
            spacing: Tokens.spacing.medium

            MaterialIcon {
                Layout.topMargin: Math.round(fontInfo.pointSize * 0.12)
                text: "lyrics"
                fontStyle: Tokens.font.icon.medium
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Lyrics")
                font: Tokens.font.title.medium
            }

            IconButton {
                icon: "open_in_full"
                type: IconButton.Text
                disabled: !Players.active
                onClicked: ImmersiveLyricsState.open((QsWindow.window as QsWindow)?.screen?.name ?? "")
            }

            IconButton {
                icon: root.toolsOpen ? "lyrics" : "tune"
                type: IconButton.Text
                onClicked: root.toolsOpen = !root.toolsOpen
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            LyricList {
                anchors.fill: parent
                visible: !root.toolsOpen
                active: root.active && visible
            }

            LyricsInfo {
                anchors.fill: parent
                visible: root.toolsOpen
                onCloseRequested: root.toolsOpen = false
            }
        }
    }
}
