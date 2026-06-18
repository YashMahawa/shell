pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    signal closeRequested()

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.large
    clip: true

    function candidateLabel(candidate: var): string {
        if (!candidate || !candidate.title)
            return qsTr("Auto");
        return candidate.title;
    }

    function candidateArtist(candidate: var): string {
        if (!candidate)
            return "";
        const backend = LyricsBackend.toString(candidate.backend);
        const artist = candidate.artist || Players.active?.trackArtist || qsTr("Unknown artist");
        return `${artist}  -  ${backend}`;
    }

    function selectedCandidateMatches(candidate: var): bool {
        const selected = Lyrics.selectedCandidate;
        if (!selected || !candidate)
            return false;
        return selected === candidate || (selected.title === candidate.title && selected.artist === candidate.artist && selected.backend === candidate.backend);
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                Layout.topMargin: Math.round(fontInfo.pointSize * 0.12)
                text: "lyrics"
                fill: 1
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.medium
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: SyllableLyrics.provider || LyricsBackend.toString(Lyrics.backend)
                    color: Colours.palette.m3secondary
                    font: Tokens.font.label.large
                    elide: Text.ElideRight
                    animate: true
                }

                StyledText {
                    Layout.fillWidth: true
                    text: SyllableLyrics.status || qsTr("Synced lyrics")
                    visible: GlobalConfig.services.showLyricsStatus
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                    animate: true
                }
            }

            IconButton {
                icon: "refresh"
                type: IconButton.Text
                onClicked: {
                    SyllableLyrics.loadedKey = "";
                    Lyrics.refresh();
                    SyllableLyrics.load();
                }
            }

            IconButton {
                icon: "close"
                type: IconButton.Text
                onClicked: root.closeRequested()
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Fetched candidates")
            visible: GlobalConfig.services.showLyricsCandidatePicker
            color: Colours.palette.m3outline
            font: Tokens.font.label.medium
            elide: Text.ElideRight
        }

        ListView {
            id: candidatesView

            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: GlobalConfig.services.showLyricsCandidatePicker
            model: Lyrics.lyricCandidates.length
            clip: true
            spacing: Tokens.spacing.small

            delegate: Item {
                id: delegateRoot

                readonly property var candidate: Lyrics.lyricCandidates[index]

                width: ListView.view.width
                height: Math.max(candidateText.implicitHeight + Tokens.padding.medium * 2, 62)

                readonly property bool selected: root.selectedCandidateMatches(candidate)
                property bool hovered: false
                property bool pressed: false

                StyledRect {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.extraSmall
                    anchors.rightMargin: Tokens.padding.extraSmall
                    color: delegateRoot.pressed ? Colours.tPalette.m3primaryContainer : delegateRoot.hovered ? Colours.tPalette.m3surfaceContainerHigh : "transparent"
                    radius: Tokens.rounding.medium
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.padding.small
                    anchors.verticalCenter: parent.verticalCenter
                    width: 4
                    height: Math.round(parent.height * 0.58)
                    radius: 2
                    color: delegateRoot.selected ? Colours.palette.m3primary : "transparent"
                }

                ColumnLayout {
                    id: candidateText

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.padding.large
                    anchors.rightMargin: Tokens.padding.medium
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        Layout.fillWidth: true
                        text: root.candidateLabel(delegateRoot.candidate)
                        color: delegateRoot.selected || delegateRoot.hovered ? Colours.palette.m3primary : Colours.palette.m3onSurface
                        font: Tokens.font.label.large
                        elide: Text.ElideRight
                        animate: true
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.candidateArtist(delegateRoot.candidate)
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                        animate: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: delegateRoot.hovered = true
                    onExited: delegateRoot.hovered = false
                    onPressed: delegateRoot.pressed = true
                    onReleased: delegateRoot.pressed = false
                    onCanceled: delegateRoot.pressed = false
                    onClicked: Lyrics.setSelectedCandidate(delegateRoot.candidate)
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: candidatesView.count === 0
                text: qsTr("No lyric tracks")
                color: Colours.palette.m3outline
                font: Tokens.font.label.large
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: GlobalConfig.services.showLyricsOffsetControls
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "contrast_square"
                color: Colours.palette.m3secondary
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                text: qsTr("Offset")
                color: Colours.palette.m3outline
                font: Tokens.font.label.large
            }

            Item {
                Layout.fillWidth: true
            }

            IconButton {
                icon: "remove"
                type: IconButton.Text
                onClicked: Lyrics.offset = Math.round((Lyrics.offset - 0.1) * 10) / 10
            }

            TextInput {
                id: offsetInput

                Layout.preferredWidth: offsetMetrics.width + Tokens.padding.medium
                horizontalAlignment: TextInput.AlignHCenter
                color: Colours.palette.m3secondary
                selectedTextColor: Colours.palette.m3onPrimary
                selectionColor: Colours.palette.m3primary
                font: Tokens.font.label.large
                selectByMouse: true
                text: (Lyrics.offset >= 0 ? "+" : "") + Lyrics.offset.toFixed(1) + "s"

                TextMetrics {
                    id: offsetMetrics

                    text: "+00.0s"
                    font: offsetInput.font
                }

                Binding {
                    target: offsetInput
                    property: "text"
                    value: (Lyrics.offset >= 0 ? "+" : "") + Lyrics.offset.toFixed(1) + "s"
                    when: !offsetInput.activeFocus
                }

                onEditingFinished: {
                    const cleaned = offsetInput.text.replace(/[+s]/g, "").trim();
                    const value = Number.parseFloat(cleaned);
                    if (Number.isNaN(value))
                        offsetInput.text = (Lyrics.offset >= 0 ? "+" : "") + Lyrics.offset.toFixed(1) + "s";
                    else
                        Lyrics.offset = Math.round(value * 10) / 10;
                }
            }

            IconButton {
                icon: "add"
                type: IconButton.Text
                onClicked: Lyrics.offset = Math.round((Lyrics.offset + 0.1) * 10) / 10
            }
        }
    }
}
