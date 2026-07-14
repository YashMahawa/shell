pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services

Item {
    id: root

    required property bool active
    readonly property real fadeAmount: 0.15
    property int lyricRevision: SyllableLyrics.revision
    property real smoothPosition: Players.active?.position ?? 0

    onActiveChanged: {
        if (!active)
            return;
        root.smoothPosition = Players.active?.position ?? 0;
        Qt.callLater(() => {
            const index = lyrics.currentIndex;
            if (index >= 0)
                lyrics.positionViewAtIndex(index, ListView.Center);
        });
    }

    layer.enabled: true
    layer.effect: Mask {
        maskSource: fadeMask

        Rectangle {
            id: fadeMask

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
                    color: "black"
                    position: root.fadeAmount
                }
                GradientStop {
                    color: "black"
                    position: 1 - root.fadeAmount
                }
                GradientStop {
                    color: Qt.alpha("black", 0)
                    position: 1
                }
            }
        }
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
        running: root.active && SyllableLyrics.hasSyllables && !!Players.active && Players.active.isPlaying
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

    Column {
        anchors.centerIn: parent
        visible: !SyllableLyrics.hasLyrics
        spacing: 12

        LoadingIndicator {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: SyllableLyrics.loading || Lyrics.loading
            implicitSize: 40
            containsIcon: true
            color: "#edf0f4"
        }

        MaterialIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !(SyllableLyrics.loading || Lyrics.loading)
            text: "lyrics"
            color: "#858e99"
            fontStyle: Tokens.font.icon.builders.large.scale(1.5).build()
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: SyllableLyrics.loading || Lyrics.loading ? qsTr("Finding the words...") : qsTr("No synced lyrics for this track")
            color: "#c9cfd6"
            font: Tokens.font.title.large
        }
    }

    StyledListView {
        id: lyrics

        anchors.fill: parent
        anchors.topMargin: parent.height * root.fadeAmount / 2
        anchors.bottomMargin: parent.height * root.fadeAmount / 2
        visible: SyllableLyrics.hasLyrics

        displayMarginBeginning: anchors.topMargin
        displayMarginEnd: anchors.bottomMargin
        model: SyllableLyrics.model
        spacing: Math.max(18, height * 0.022)
        pixelAligned: false
        readonly property real focusLineHeight: Math.max(72, Math.min(96, width * 0.11))

        Component.onCompleted: {
            currentIndex = Qt.binding(() => {
                model;
                return SyllableLyrics.indexForTime(root.smoothPosition);
            });
            positionViewAtIndex(currentIndex, ListView.Center);
        }
        onModelChanged: Qt.callLater(() => positionViewAtIndex(currentIndex, ListView.Center))

        highlightRangeMode: ListView.StrictlyEnforceRange
        highlightMoveDuration: 720
        highlightMoveVelocity: -1
        preferredHighlightBegin: (height - focusLineHeight) / 2
        preferredHighlightEnd: (height + focusLineHeight) / 2

        delegate: Item {
            id: line

            required property string lyricLine
            required property string syllabus
            required property int index

            readonly property bool current: ListView.isCurrentItem
            readonly property int distanceFromCurrent: Math.abs(index - lyrics.currentIndex)
            readonly property font lineFont: Qt.font({
                family: Tokens.font.headline.large.family,
                pixelSize: Math.max(30, Math.min(45, lyrics.width * 0.056)),
                weight: Font.DemiBold
            })

            width: lyrics.width - 18
            implicitHeight: Math.max(plainLine.implicitHeight, karaokeLoader.implicitHeight) + 16
            height: implicitHeight
            x: current ? 16 : 0
            opacity: current ? 1 : Math.max(0.19, 0.58 - distanceFromCurrent * 0.12)

            Text {
                id: plainLine

                width: parent.width
                visible: !line.current || !SyllableLyrics.hasSyllables
                text: line.lyricLine || ". . ."
                color: line.current ? "#d8dde5" : line.index < lyrics.currentIndex ? "#a8b0ba" : "#858e99"
                font: line.lineFont
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                renderType: Text.QtRendering
                renderTypeQuality: Text.VeryHighRenderTypeQuality
            }

            Loader {
                id: karaokeLoader

                width: parent.width
                active: line.current && SyllableLyrics.hasSyllables
                visible: active

                sourceComponent: KaraokeLine {
                    width: karaokeLoader.width
                    lineText: line.lyricLine
                    syllabus: line.syllabus
                    position: root.smoothPosition - Lyrics.offset + 0.1
                    lyricFont: line.lineFont
                    waitingColor: "#68727e"
                    activeColor: "#d8dde5"
                }
            }

            Behavior on x {
                SpringAnimation {
                    spring: 4.2
                    damping: 0.34
                    epsilon: 0.2
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 360
                    easing.type: Easing.OutCubic
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: SyllableLyrics.jumpTo(line.index)
            }
        }
    }

    Behavior on lyricRevision {
        SequentialAnimation {
            NumberAnimation {
                target: lyrics
                property: "opacity"
                to: 0
                duration: 130
                easing.type: Easing.OutCubic
            }
            PropertyAction {}
            NumberAnimation {
                target: lyrics
                property: "opacity"
                to: 1
                duration: 380
                easing.type: Easing.OutCubic
            }
        }
    }
}
