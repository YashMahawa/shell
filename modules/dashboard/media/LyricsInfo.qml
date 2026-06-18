import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Blobs
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    property bool open
    readonly property real padding: Tokens.padding.large
    readonly property bool hasVisibleTools: (GlobalConfig.services.showLyricsProviderDetails || (GlobalConfig.services.showLyricsStatus && SyllableLyrics.status.length > 0) || GlobalConfig.services.showLyricsOffsetControls || (GlobalConfig.services.showLyricsCandidatePicker && Lyrics.lyricCandidates.length > 0))

    implicitWidth: btn.implicitWidth * 0.9
    implicitHeight: btn.implicitHeight * 0.9

    function clean(value: string): string {
        return String(value || "").toLowerCase().replace(/\s*\(.*?\)/g, "").replace(/\s*\[.*?\]/g, "").trim();
    }

    function candidateLabel(candidate: var): string {
        if (!candidate || !candidate.title)
            return qsTr("Auto")
        const backend = LyricsBackend.toString(candidate.backend);
        const artist = candidate.artist || Players.active?.trackArtist || "";
        return `${backend}: ${candidate.title}${artist ? " - " + artist : ""}`;
    }

    function selectedCandidateMatches(): bool {
        const selected = Lyrics.selectedCandidate;
        const active = Players.active;
        if (!selected || !selected.title || !active)
            return false;
        const selectedTitle = clean(selected.title);
        const activeTitle = clean(active.trackTitle);
        if (!selectedTitle || !activeTitle || selectedTitle !== activeTitle)
            return false;
        const selectedArtist = clean(selected.artist).split(/[&,xX]/)[0].trim();
        const activeArtist = clean(active.trackArtist).split(/[&,xX]/)[0].trim();
        return !selectedArtist || !activeArtist || selectedArtist === activeArtist || selectedArtist.includes(activeArtist) || activeArtist.includes(selectedArtist);
    }

    BlobGroup {
        id: blobGroup

        color: Colours.palette.m3surfaceContainerHighest
        smoothing: root.Tokens.rounding.medium
        cornerFill: false
        lod: GameMode.enabled || !root.Window.active

        Behavior on color {
            CAnim {}
        }
    }

    BlobRect {
        id: btnRect

        anchors.fill: parent
        anchors.margins: !btn.pressed && btn.containsMouse ? -Tokens.padding.extraSmall : 0
        group: blobGroup
        radius: Tokens.rounding.medium

        Behavior on anchors.margins {
            Anim {}
        }
    }

    BlobRect {
        id: rect

        anchors.right: parent.right
        anchors.top: parent.top

        implicitWidth: parent.width
        implicitHeight: parent.height

        group: blobGroup
        radius: Tokens.rounding.medium
        deformScale: 0.00001

        states: State {
            name: "open"
            when: root.open

            PropertyChanges {
                rect.anchors.rightMargin: root.width + root.Tokens.spacing.large
                rect.anchors.topMargin: -root.Tokens.padding.medium
                rect.implicitWidth: Math.max(layout.implicitWidth, placeholder.implicitWidth) + root.padding * 2
                rect.implicitHeight: Math.max(layout.implicitHeight, placeholder.implicitHeight) + root.padding * 2
                content.opacity: 1
            }
        }

        transitions: Transition {
            Anim {
                properties: "rightMargin,implicitWidth"
            }
            Anim {
                properties: "topMargin,implicitHeight"
                easing: root.Tokens.anim.expressiveFastSpatial
            }
            Anim {
                property: "opacity"
                type: Anim.DefaultEffects
            }
        }

        Behavior on implicitWidth {
            Anim {}
        }

        Behavior on implicitHeight {
            Anim {}
        }

        Item {
            id: content

            anchors.fill: parent
            clip: true
            opacity: 0
            state: SyllableLyrics.loading ? "" : SyllableLyrics.hasLyrics || root.hasVisibleTools ? "hasLyrics" : ""

            states: State {
                name: "hasLyrics"

                PropertyChanges {
                    layout.opacity: 1
                    placeholder.opacity: 0
                }
            }

            transitions: [
                Transition {
                    from: "hasLyrics"

                    SequentialAnimation {
                        Anim {
                            target: layout
                            property: "opacity"
                            type: Anim.FastEffects
                        }
                        Anim {
                            target: placeholder
                            property: "opacity"
                            type: Anim.DefaultEffects
                        }
                    }
                },
                Transition {
                    to: "hasLyrics"

                    SequentialAnimation {
                        Anim {
                            target: placeholder
                            property: "opacity"
                            type: Anim.FastEffects
                        }
                        Anim {
                            target: layout
                            property: "opacity"
                            type: Anim.DefaultEffects
                        }
                    }
                }
            ]

            ColumnLayout {
                id: layout

                anchors.centerIn: parent
                spacing: Tokens.spacing.small
                opacity: 0

                StyledText {
                    Layout.maximumWidth: Tokens.sizes.dashboard.mediaTabWidth / 2
                    visible: GlobalConfig.services.showLyricsProviderDetails
                    text: qsTr("Backend: %1").arg(SyllableLyrics.provider || LyricsBackend.toString(Lyrics.backend))
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    animate: true
                }

                StyledText {
                    Layout.maximumWidth: Tokens.sizes.dashboard.mediaTabWidth / 2
                    visible: GlobalConfig.services.showLyricsStatus && SyllableLyrics.status.length > 0
                    text: SyllableLyrics.status
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    animate: true
                }

                StyledText {
                    Layout.maximumWidth: Tokens.sizes.dashboard.mediaTabWidth / 2
                    visible: GlobalConfig.services.showLyricsProviderDetails
                    text: qsTr("Track: %1 - %2").arg(Players.active?.trackArtist || qsTr("Unknown")).arg(Players.active?.trackTitle || qsTr("Unknown"))
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    animate: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: GlobalConfig.services.showLyricsOffsetControls
                    spacing: Tokens.spacing.small

                    IconButton {
                        icon: "keyboard_double_arrow_left"
                        type: IconButton.Tonal
                        onClicked: Lyrics.offset = Math.round((Lyrics.offset - 0.5) * 10) / 10
                    }

                    IconButton {
                        icon: "keyboard_arrow_left"
                        type: IconButton.Tonal
                        onClicked: Lyrics.offset = Math.round((Lyrics.offset - 0.1) * 10) / 10
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: qsTr("Offset: %1 ms").arg(Math.round(Lyrics.offset * 1000))
                        color: Colours.palette.m3onSurfaceVariant
                        animate: true
                    }

                    IconButton {
                        icon: "keyboard_arrow_right"
                        type: IconButton.Tonal
                        onClicked: Lyrics.offset = Math.round((Lyrics.offset + 0.1) * 10) / 10
                    }

                    IconButton {
                        icon: "keyboard_double_arrow_right"
                        type: IconButton.Tonal
                        onClicked: Lyrics.offset = Math.round((Lyrics.offset + 0.5) * 10) / 10
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: GlobalConfig.services.showLyricsCandidatePicker
                    spacing: Tokens.spacing.small

                    SplitButton {
                        Layout.fillWidth: true
                        type: SplitButton.Tonal
                        disabled: Lyrics.lyricCandidates.length === 0
                        menuOnTop: false
                        menuItems: candidateVariants.instances
                        active: selectedCandidateMatches() ? menuItems.find(i => i.modelData === Lyrics.selectedCandidate) ?? null : null
                        fallbackIcon: "lyrics"
                        fallbackText: Lyrics.lyricCandidates.length ? qsTr("Pick lyrics") : qsTr("No lyric tracks")
                        minLeftWidth: Math.min(360, layout.width - refreshBtn.implicitWidth - Tokens.spacing.small)
                        label.Layout.maximumWidth: minLeftWidth - expandBtn.implicitWidth - iconLabel.implicitWidth - textRow.spacing - horizontalPadding * 2
                        label.elide: Text.ElideRight
                        menu.onItemSelected: item => Lyrics.setSelectedCandidate(item.modelData)
                    }

                    IconButton {
                        id: refreshBtn

                        icon: "refresh"
                        type: IconButton.Tonal
                        onClicked: {
                            SyllableLyrics.loadedKey = "";
                            Lyrics.refresh();
                            SyllableLyrics.load();
                        }
                    }
                }
            }

            Item {
                id: placeholder

                anchors.centerIn: parent
                implicitWidth: placeholderText.implicitWidth
                implicitHeight: placeholderText.implicitHeight

                StyledText {
                    id: placeholderText

                    text: SyllableLyrics.loading ? qsTr("Loading...") : SyllableLyrics.status || qsTr("No lyrics found")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                    animate: true
                }
            }
        }
    }

    MouseArea {
        id: btn

        anchors.centerIn: parent
        implicitWidth: implicitHeight
        implicitHeight: icon.implicitHeight + Tokens.padding.extraSmall * 2
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: root.open = !root.open

        MaterialIcon {
            id: icon

            anchors.centerIn: parent
            text: "more_vert"
            fontStyle: Tokens.font.icon.medium
        }
    }

    Variants {
        id: candidateVariants

        model: Lyrics.lyricCandidates

        CandidateItem {}
    }

    component CandidateItem: MenuItem {
        required property var modelData

        text: root.candidateLabel(modelData)
        icon: modelData === Lyrics.selectedCandidate ? "check" : ""
        activeIcon: LyricsBackend.toString(modelData.backend) === "NetEase" ? "music_note" : "lyrics"
    }
}
