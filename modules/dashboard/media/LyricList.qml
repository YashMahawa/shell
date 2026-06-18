pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services

Item {
    id: root

    // Funny binding hack to make lyrics update
    readonly property var _: {
        const p = Players.active;
        if (p)
            Lyrics.setTrack(p.trackArtist, p.trackTitle, p.trackAlbum, p.length);
        else
            Lyrics.clearTrack();
    }

    readonly property real fadeAmount: 0.1
    property bool flag
    property int lyricRevision: SyllableLyrics.revision
    property real smoothPosition: Players.active?.position ?? 0

    layer.enabled: true
    layer.effect: Mask {
        maskSource: mask

        Rectangle {
            id: mask

            layer.enabled: true
            visible: false
            implicitWidth: root.width
            implicitHeight: root.height

            gradient: Gradient {
                orientation: Gradient.Vertical

                GradientStop {
                    color: Qt.alpha("black", 0)
                    position: 0
                }
                GradientStop {
                    color: Qt.alpha("black", 1)
                    position: root.fadeAmount
                }
                GradientStop {
                    color: Qt.alpha("black", 1)
                    position: 1 - root.fadeAmount
                }
                GradientStop {
                    color: Qt.alpha("black", 0)
                    position: 1
                }
            }
        }
    }

    state: {
        flag; // For some reason it doesn't update sometimes, so use this to force an update
        if (SyllableLyrics.hasLyrics)
            return "hasLyrics";
        if (SyllableLyrics.loading || Lyrics.loading)
            return "loading";
        return "noLyrics";
    }

    states: [
        State {
            name: "loading"

            PropertyChanges {
                loadingIndicator.opacity: 1
                lyrics.opacity: 0
                noLyrics.opacity: 0
            }
        },
        State {
            name: "hasLyrics"

            PropertyChanges {
                loadingIndicator.opacity: 0
                lyrics.opacity: 1
                noLyrics.opacity: 0
            }
        },
        State {
            name: "noLyrics"

            PropertyChanges {
                loadingIndicator.opacity: 0
                lyrics.opacity: 0
                noLyrics.opacity: 1
            }
        }
    ]

    transitions: [
        Transition {
            from: "loading"

            SequentialAnimation {
                Anim {
                    target: loadingIndicator
                    property: "opacity"
                    type: Anim.DefaultEffects
                }
                Anim {
                    targets: [lyrics, noLyrics]
                    property: "opacity"
                    type: Anim.SlowEffects
                }
            }
        },
        Transition {
            from: "hasLyrics"

            SequentialAnimation {
                Anim {
                    target: lyrics
                    property: "opacity"
                    type: Anim.DefaultEffects
                }
                Anim {
                    targets: [loadingIndicator, noLyrics]
                    property: "opacity"
                    type: Anim.SlowEffects
                }
            }
        },
        Transition {
            from: "noLyrics"

            SequentialAnimation {
                Anim {
                    target: noLyrics
                    property: "opacity"
                    type: Anim.DefaultEffects
                }
                Anim {
                    targets: [loadingIndicator, lyrics]
                    property: "opacity"
                    type: Anim.SlowEffects
                }
            }
        }
    ]

    Connections {
        function onHasLyricsChanged() {
            root.flag = !root.flag;
        }

        target: Lyrics
    }

    Connections {
        function onRevisionChanged() {
            root.flag = !root.flag;
        }

        target: SyllableLyrics
    }

    Connections {
        target: Players.active
        ignoreUnknownSignals: true

        function onPositionChanged(): void {
            root.smoothPosition = Players.active?.position ?? 0;
            if (smoothTicker.running)
                smoothTicker.lastRealTime = Date.now() / 1000;
        }
    }

    Timer {
        id: smoothTicker

        interval: 16
        running: SyllableLyrics.hasSyllables && !!Players.active && Players.active.isPlaying
        repeat: true

        property real lastRealTime: 0

        onTriggered: {
            const now = Date.now() / 1000;
            if (lastRealTime > 0)
                root.smoothPosition += now - lastRealTime;
            lastRealTime = now;
        }

        onRunningChanged: {
            if (running) {
                root.smoothPosition = Players.active?.position ?? 0;
                lastRealTime = Date.now() / 1000;
            } else {
                lastRealTime = 0;
            }
        }
    }

    Loader {
        id: loadingIndicator

        anchors.centerIn: parent
        asynchronous: true
        active: opacity > 0
        opacity: 0

        sourceComponent: ColumnLayout {
            spacing: Tokens.spacing.large

            StyledRect {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: shape.implicitSize + Tokens.padding.medium * 2
                implicitHeight: shape.implicitSize + Tokens.padding.medium * 2
                color: Colours.palette.m3primaryContainer
                radius: Tokens.rounding.full

                LoadingIndicator {
                    id: shape

                    anchors.centerIn: parent
                    implicitSize: Math.round(Tokens.sizes.dashboard.mediaSectionWidth / 5)
                    containsIcon: true // This removes the pentagon, which is not centered
                }
            }

            StyledText {
                text: qsTr("Loading lyrics...")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.title.medium
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        id: noLyrics

        anchors.centerIn: parent
        asynchronous: true
        active: opacity > 0
        opacity: 0

        sourceComponent: ColumnLayout {
            spacing: Tokens.spacing.small

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: "sentiment_sad"
                fontStyle: Tokens.font.icon.builders.large.scale(2).build()
                color: Colours.palette.m3outline
            }

            StyledText {
                text: qsTr("No lyrics found")
                color: Colours.palette.m3outline
                font: Tokens.font.title.medium
            }
        }
    }

    StyledListView {
        id: lyrics

        anchors.fill: parent
        anchors.topMargin: parent.height * root.fadeAmount / 2
        anchors.bottomMargin: parent.height * root.fadeAmount / 2

        displayMarginBeginning: anchors.topMargin
        displayMarginEnd: anchors.bottomMargin

        model: SyllableLyrics.model
        Component.onCompleted: {
            currentIndex = Qt.binding(() => {
                model; // Force update when lyrics change
                return SyllableLyrics.hasSyllables ? SyllableLyrics.indexForTime(root.smoothPosition) : SyllableLyrics.currentIndex;
            });
            positionViewAtIndex(currentIndex, ListView.Center);
        }
        onModelChanged: Qt.callLater(() => positionViewAtIndex(currentIndex, ListView.Center))

        highlightRangeMode: ListView.ApplyRange
        highlightMoveDuration: Tokens.anim.durations.large
        highlightMoveVelocity: -1
        preferredHighlightBegin: (height - (currentItem?.implicitHeight ?? 0)) / 2
        preferredHighlightEnd: (height + (currentItem?.implicitHeight ?? 0)) / 2

        spacing: Tokens.spacing.small
        opacity: 0

        delegate: StyledText {
            id: lyric

            required property string lyricLine
            required property string syllabus
            required property int index
            property real effectScale: ListView.isCurrentItem ? 1 : 0
            readonly property string highlightedText: {
                const baseText = lyric.lyricLine || ". . .";
                let syllabusArray = [];
                if (SyllableLyrics.hasSyllables && lyric.syllabus) {
                    try {
                        syllabusArray = JSON.parse(lyric.syllabus);
                    } catch (e) {
                        syllabusArray = [];
                    }
                }
                if (!ListView.isCurrentItem || syllabusArray.length === 0)
                    return baseText;

                function colorToHex(c) {
                    const s = c.toString();
                    return s.length === 9 ? "#" + s.substring(3, 9) : s;
                }

                function interpolateColor(a, b, factor) {
                    const r1 = parseInt(a.substring(1, 3), 16);
                    const g1 = parseInt(a.substring(3, 5), 16);
                    const b1 = parseInt(a.substring(5, 7), 16);
                    const r2 = parseInt(b.substring(1, 3), 16);
                    const g2 = parseInt(b.substring(3, 5), 16);
                    const b2 = parseInt(b.substring(5, 7), 16);
                    const r = Math.round(r1 + factor * (r2 - r1)).toString(16).padStart(2, "0");
                    const g = Math.round(g1 + factor * (g2 - g1)).toString(16).padStart(2, "0");
                    const bl = Math.round(b1 + factor * (b2 - b1)).toString(16).padStart(2, "0");
                    return "#" + r + g + bl;
                }

                function escapeHtml(s) {
                    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
                }

                const pos = root.smoothPosition;
                const activeColor = colorToHex(Colours.palette.m3primary);
                const inactiveColor = interpolateColor("#121212", activeColor, 0.28);
                let html = "";

                for (const syl of syllabusArray) {
                    const text = escapeHtml(syl.text || "");
                    const start = Number(syl.time || 0);
                    const duration = Math.max(Number(syl.duration || 0.2), 0.05);
                    if (text.length <= 1 || pos < start || pos >= start + duration) {
                        const factor = pos >= start ? 1 : 0;
                        html += `<span style="color: ${interpolateColor(inactiveColor, activeColor, factor)}">${text}</span>`;
                        continue;
                    }

                    const charDuration = duration / text.length;
                    for (let i = 0; i < text.length; i++) {
                        const charStart = start + i * charDuration;
                        let factor = 0;
                        if (pos >= charStart)
                            factor = pos >= charStart + charDuration ? 1 : (pos - charStart) / charDuration;
                        html += `<span style="color: ${interpolateColor(inactiveColor, activeColor, factor)}">${text[i]}</span>`;
                    }
                }

                return html;
            }

            anchors.left: lyrics.contentItem.left
            anchors.right: lyrics.contentItem.right

            text: highlightedText
            textFormat: SyllableLyrics.hasSyllables ? Text.RichText : Text.PlainText
            color: ListView.isCurrentItem ? Colours.palette.m3primary : mouse.containsMouse ? Colours.palette.m3onSurface : Colours.palette.m3outline
            font: Tokens.font.body.medium
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere

            Behavior on effectScale {
                Anim {
                    type: Anim.SlowEffects
                }
            }

            MouseArea {
                id: mouse

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: {
                    SyllableLyrics.jumpTo(lyric.index);
                }
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }

    Behavior on lyricRevision {
        SequentialAnimation {
            Anim {
                target: lyrics
                property: "opacity"
                to: 0
                type: Anim.DefaultEffects
            }
            PropertyAction {}
            Anim {
                target: lyrics
                property: "opacity"
                to: 1
                type: Anim.SlowEffects
            }
        }
    }
}
