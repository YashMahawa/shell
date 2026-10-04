pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services

// Apple Music style lyric column.
//
// The active line sits near the top. When it changes, the column jumps to its
// new position and every visible line is given an equal and opposite offset
// that then springs back with a small per-line delay, which produces the
// cascading scroll. Scrolling with the wheel browses freely (and unblurs);
// after a short pause the view returns to the song.
Item {
    id: root

    required property bool active
    property bool retained: false
    property bool reduceMotion: false
    // Theming, so the dashboard can reuse this renderer.
    property color textColor: "white"
    property color activeColor: textColor
    property int fontPixelSize: Math.round(Math.max(32, Math.min(58, width * 0.07)))
    property real anchorRatio: 0.18
    property real fadeTop: 0.16
    property real fadeBottom: 0.5

    property real position: 0
    property real focusY: 0
    readonly property real columnY: column.y
    property int currentIndex: -1
    property int interludeIndex: -1
    property real interludeProgress: -1
    property real manualOffset: 0
    property bool userScrolling: false
    property bool animateScroll: false
    property var starts: []
    property var ends: []

    readonly property font lyricFont: Qt.font({
        family: Tokens.font.headline.large.family,
        pixelSize: root.fontPixelSize,
        weight: Font.Bold,
        variableAxes: { "wght": 500, "ROND": 30, "opsz": 40 }
    })

    function syncRetention(): void {
        if (active && !retained) {
            SyllableLyrics.retain();
            retained = true;
        } else if (!active && retained) {
            SyllableLyrics.release();
            retained = false;
        }
    }

    function rebuildTimes(): void {
        const model = SyllableLyrics.model;
        const s = [];
        const e = [];
        for (let i = 0; i < model.count; i++) {
            const row = model.get(i);
            s.push(row.time);
            e.push(row.time + Math.max(0, row.duration || 0));
        }
        starts = s;
        ends = e;
    }

    // Instrumental breaks of at least four seconds (including the intro) show
    // the breathing dots in place of the next line.
    function updateInterlude(time: real): void {
        let index = -1;
        let progress = -1;
        const next = currentIndex + 1;
        if (next < starts.length) {
            const gapStart = currentIndex >= 0 ? ends[currentIndex] : 0;
            const gapEnd = starts[next];
            if (gapEnd - gapStart >= 4 && time >= gapStart && time < gapEnd - 0.12) {
                index = next;
                progress = (time - gapStart) / (gapEnd - gapStart);
            }
        }
        if (index !== interludeIndex)
            interludeIndex = index;
        interludeProgress = progress;
    }

    function focusIndex(): int {
        return interludeIndex >= 0 ? interludeIndex : Math.max(0, currentIndex);
    }

    // The column is bound to the focused line's live y, so relayouts above it
    // (karaoke words building, interlude dots collapsing) never move it.
    function updateFocusY(): void {
        const item = repeater.itemAt(focusIndex());
        if (item)
            focusY = item.y;
    }

    function lineMoved(index: int, y: real): void {
        if (index === focusIndex())
            focusY = y;
    }

    // Called when the focused line changes: the column jumps to the new line
    // and visible lines spring back from where they were, staggered.
    function refocus(animated: bool): void {
        const before = column.y;
        updateFocusY();
        const delta = column.y - before;
        if (!animated || Math.abs(delta) < 0.5 || reduceMotion)
            return;
        const focus = focusIndex();
        for (let i = Math.max(0, focus - 3); i < Math.min(repeater.count, focus + 12); i++) {
            const item = repeater.itemAt(i);
            if (item)
                item.shift(-delta, i < focus ? 0 : 24 + (i - focus) * 38);
        }
    }

    function tick(): void {
        const player = Players.active;
        if (!player)
            return;
        const time = player.position - Lyrics.offset + 0.1;
        position = time;
        const index = SyllableLyrics.indexForTime(player.position);
        if (index !== currentIndex)
            currentIndex = index;
        updateInterlude(time);
    }

    Component.onCompleted: {
        syncRetention();
        rebuildTimes();
    }
    Component.onDestruction: {
        if (retained)
            SyllableLyrics.release();
    }

    onActiveChanged: {
        syncRetention();
        if (!active)
            return;
        animateScroll = false;
        manualOffset = 0;
        userScrolling = false;
        tick();
        Qt.callLater(() => {
            refocus(false);
            animateScroll = true;
        });
    }
    onCurrentIndexChanged: refocus(animateScroll)
    onInterludeIndexChanged: refocus(animateScroll)

    Connections {
        target: SyllableLyrics

        function onRevisionChanged(): void {
            root.animateScroll = false;
            root.rebuildTimes();
            root.tick();
            Qt.callLater(() => {
                root.refocus(false);
                root.animateScroll = true;
            });
        }
    }

    // Reading the MPRIS position is an interpolated clock in Quickshell, so
    // one cheap read per displayed frame keeps word timing exact.
    FrameAnimation {
        running: root.active && root.visible && SyllableLyrics.hasLyrics && (Players.active?.isPlaying ?? false)
        onTriggered: root.tick()
    }

    Connections {
        target: Players.active
        ignoreUnknownSignals: true

        function onPositionChanged(): void {
            root.tick();
        }
    }

    Column {
        anchors.centerIn: parent
        visible: !SyllableLyrics.hasLyrics
        spacing: 14
        opacity: visible ? 1 : 0

        LoadingIndicator {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: SyllableLyrics.loading || Lyrics.loading
            implicitSize: 40
            containsIcon: true
            color: root.textColor
        }

        MaterialIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !(SyllableLyrics.loading || Lyrics.loading)
            text: "lyrics"
            color: Qt.alpha(root.textColor, 0.55)
            fontStyle: Tokens.font.icon.builders.large.scale(1.5).build()
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: SyllableLyrics.loading || Lyrics.loading ? qsTr("Finding the words...") : qsTr("No synced lyrics for this track")
            color: Qt.alpha(root.textColor, 0.78)
            font: root.fontPixelSize < 30 ? Tokens.font.title.medium : Tokens.font.title.large
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 300
            }
        }
    }

    Item {
        id: viewport

        anchors.fill: parent
        visible: SyllableLyrics.hasLyrics
        clip: false

        Column {
            id: column

            y: Math.round(root.height * root.anchorRatio - root.focusY + root.manualOffset)
            x: root.lyricFont.pixelSize * 0.4
            width: parent.width - root.lyricFont.pixelSize * 0.8
            spacing: Math.round(root.lyricFont.pixelSize * 0.56)

            Repeater {
                id: repeater

                model: SyllableLyrics.model

                LyricLine {
                    list: root
                    textColor: root.textColor
                    activeColor: root.activeColor
                    currentIndex: root.currentIndex
                    userScrolling: root.userScrolling
                    reduceMotion: root.reduceMotion
                    lyricFont: root.lyricFont
                    maxWidth: column.width
                    interludeIndex: root.interludeIndex
                    onYChanged: root.lineMoved(index, y)
                    onSeekRequested: index => {
                        SyllableLyrics.jumpTo(index);
                        root.manualOffset = 0;
                        root.userScrolling = false;
                        returnTimer.stop();
                    }
                }
            }
        }
    }

    Behavior on manualOffset {
        enabled: !root.userScrolling

        NumberAnimation {
            duration: 700
            easing.type: Easing.OutCubic
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            root.userScrolling = true;
            const step = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 120 * root.lyricFont.pixelSize * 2;
            const limit = Math.max(root.height, column.height);
            root.manualOffset = Math.max(-limit, Math.min(limit, root.manualOffset + step));
            returnTimer.restart();
        }
    }

    Timer {
        id: returnTimer

        interval: 2800
        repeat: false
        onTriggered: {
            root.userScrolling = false;
            root.manualOffset = 0;
        }
    }
}
