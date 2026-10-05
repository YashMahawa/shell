pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

// One lyric line in the immersive view.
//
// Inactive lines are a single Text item. The active line and its neighbours
// are built from timed words so the hand-over between lines never has to
// instantiate anything on the frame it happens.
Item {
    id: line

    required property int index
    required property string lyricLine
    required property real time
    required property real duration
    required property string syllabus
    required property string agent
    required property string bgText
    required property string bgSyllabus

    // The list owns the hot per-frame state (position, interlude progress);
    // only the active line reads it, so other lines do no work per frame.
    required property Item list
    required property color textColor
    required property color activeColor
    required property int currentIndex
    required property bool userScrolling
    required property bool reduceMotion
    required property font lyricFont
    required property real maxWidth
    // Index of the line whose preceding instrumental break is playing, and
    // how far through that break we are.
    required property int interludeIndex

    signal seekRequested(int index)

    // During an instrumental break the dots (on the next line) take focus, so
    // the line before them fades and blurs like any other sung line.
    readonly property bool hostsInterlude: interludeIndex === index
    readonly property int focusIndex: interludeIndex >= 0 ? interludeIndex : currentIndex
    readonly property int distance: index - focusIndex
    readonly property bool current: distance === 0 && !hostsInterlude
    readonly property bool near: distance >= -1 && distance <= 2
    readonly property real livePosition: current ? list.position : -1
    readonly property bool alignEnd: agent === "end"
    readonly property var words: parseWords(syllabus)
    readonly property var bgWords: parseWords(bgSyllabus)
    readonly property bool timed: words.length > 0
    readonly property font bgFont: Qt.font({
        family: lyricFont.family,
        pixelSize: Math.round(lyricFont.pixelSize * 0.68),
        weight: Font.DemiBold,
        variableAxes: { "wght": 460, "ROND": 30 }
    })

    // Apple Music: the line being sung is bright, the one just sung blurs as
    // it leaves the top, upcoming lines stay sharp and fade with distance.
    readonly property real targetOpacity: {
        if (userScrolling)
            return current ? 1 : 0.46;
        if (current)
            return 1;
        // The line under the dots is still upcoming text.
        if (hostsInterlude)
            return 0.44;
        if (distance < 0)
            return Math.max(0.12, 0.3 + distance * 0.06);
        return Math.max(0.1, 0.44 - (distance - 1) * 0.085);
    }
    readonly property real targetBlur: userScrolling || reduceMotion || distance >= 0 ? 0 : Math.min(1, 0.5 + (-distance - 1) * 0.2)

    property real lag: 0

    // Fade towards the viewport edges: short at the top, where the line just
    // sung slides away, long at the bottom. Only changes while lines move.
    readonly property real viewY: list.columnY + y + lag
    readonly property real edgeOpacity: {
        const h = list.height;
        if (h <= 0)
            return 1;
        const top = Math.max(0, Math.min(1, (viewY + height * 0.5) / (h * list.fadeTop)));
        const fromBottom = (h - viewY) / (h * list.fadeBottom);
        const bottom = Math.max(0, Math.min(1, fromBottom));
        return top * top * (bottom * bottom * (3 - 2 * bottom));
    }

    function parseWords(encoded: string): var {
        let syllables = [];
        try {
            syllables = JSON.parse(encoded || "[]");
        } catch (error) {
            syllables = [];
        }
        // Group syllables into words so wrapping never splits a word.
        const groups = [];
        let currentGroup = [];
        for (const syllable of syllables) {
            if (!String(syllable.text || "").length)
                continue;
            currentGroup.push(syllable);
            if (/\s$/.test(syllable.text)) {
                groups.push(currentGroup);
                currentGroup = [];
            }
        }
        if (currentGroup.length)
            groups.push(currentGroup);
        return groups;
    }

    function shift(delta: real, delay: int): void {
        settle.stop();
        lag += delta;
        pause.duration = delay;
        settle.start();
    }

    width: maxWidth
    implicitHeight: dots.height + body.implicitHeight + (bgLoader.active ? bgLoader.implicitHeight + lyricFont.pixelSize * 0.12 : 0) + lyricFont.pixelSize * 0.32
    height: implicitHeight
    opacity: edgeOpacity
    scale: current || hostsInterlude || userScrolling ? 1 : 0.965
    transformOrigin: alignEnd ? Item.Right : Item.Left
    transform: Translate {
        y: line.lag
    }

    layer.enabled: blurAmount > 0.01
    layer.effect: MultiEffect {
        blurEnabled: true
        blur: line.blurAmount
        blurMax: 22
        autoPaddingEnabled: true
    }

    property real blurAmount: targetBlur
    property real shownOpacity: targetOpacity

    Behavior on shownOpacity {
        NumberAnimation {
            duration: 380
            easing.type: Easing.OutCubic
        }
    }

    Behavior on blurAmount {
        NumberAnimation {
            duration: 420
            easing.type: Easing.OutCubic
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: 560
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.25, 1, 0.5, 1, 1, 1]
        }
    }

    SequentialAnimation {
        id: settle

        PauseAnimation {
            id: pause

            duration: 0
        }
        NumberAnimation {
            target: line
            property: "lag"
            to: 0
            duration: line.reduceMotion ? 1 : 680
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -line.lyricFont.pixelSize * 0.4
        anchors.rightMargin: -line.lyricFont.pixelSize * 0.4
        radius: line.lyricFont.pixelSize * 0.35
        color: line.textColor
        opacity: hover.hovered ? 0.07 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 180
            }
        }
    }

    Item {
        id: dots

        readonly property bool shown: line.interludeIndex === line.index
        // Latched so the dots finish their exit at full fill instead of
        // emptying the moment the break ends.
        property real latchedProgress: -1

        width: parent.width
        height: shown ? interlude.implicitHeight + line.lyricFont.pixelSize * 0.45 : 0
        opacity: shown ? 1 : 0

        Behavior on height {
            SequentialAnimation {
                PauseAnimation {
                    duration: dots.shown ? 0 : 180
                }
                NumberAnimation {
                    duration: 480
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.25, 1, 0.5, 1, 1, 1]
                }
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: dots.shown ? 420 : 240
                easing.type: Easing.OutCubic
            }
        }

        Connections {
            target: line.list
            enabled: dots.shown

            function onInterludeProgressChanged(): void {
                if (line.list.interludeProgress >= 0)
                    dots.latchedProgress = line.list.interludeProgress;
            }
        }

        InterludeDots {
            id: interlude

            x: line.alignEnd ? parent.width - implicitWidth : 0
            y: line.lyricFont.pixelSize * 0.1
            dotSize: Math.round(line.lyricFont.pixelSize * 0.38)
            progress: dots.latchedProgress
            color: line.activeColor
            reduceMotion: line.reduceMotion
            visible: dots.opacity > 0.01
        }
    }

    // Lines from the answering singer sit on the right, as in Apple Music:
    // every wrapped row, the karaoke words and the backing vocal align right.
    Item {
        id: body

        opacity: line.shownOpacity
        y: dots.height
        width: line.maxWidth
        implicitHeight: karaoke.visible ? karaoke.implicitHeight : plain.implicitHeight
        height: implicitHeight

        Text {
            id: plain

            width: parent.width
            visible: !karaoke.visible
            text: line.lyricLine || ". . ."
            font: line.lyricFont
            color: line.current ? line.activeColor : line.textColor
            horizontalAlignment: line.alignEnd ? Text.AlignRight : Text.AlignLeft
            wrapMode: Text.WordWrap
            renderType: Text.QtRendering
        }

        Loader {
            id: karaoke

            width: parent.width
            active: line.timed && line.near
            visible: active && line.current && status === Loader.Ready
            sourceComponent: KaraokeRows {
                groups: line.words
                font: line.lyricFont
                maxWidth: body.width
                alignEnd: line.alignEnd
                position: line.livePosition
                color: line.activeColor
                reduceMotion: line.reduceMotion
            }
        }
    }

    Loader {
        id: bgLoader

        anchors.top: body.bottom
        anchors.topMargin: line.lyricFont.pixelSize * 0.12
        width: line.maxWidth
        active: !!line.bgText
        opacity: 0.82 * line.shownOpacity
        sourceComponent: line.bgWords.length && line.current ? bgTimed : bgPlain
    }

    Component {
        id: bgPlain

        Text {
            width: line.maxWidth
            text: line.bgText
            font: line.bgFont
            color: line.current ? line.activeColor : line.textColor
            opacity: line.current ? 0.6 : 1
            horizontalAlignment: line.alignEnd ? Text.AlignRight : Text.AlignLeft
            wrapMode: Text.WordWrap
            renderType: Text.QtRendering
        }
    }

    Component {
        id: bgTimed

        KaraokeRows {
            groups: line.bgWords
            font: line.bgFont
            maxWidth: line.maxWidth
            alignEnd: line.alignEnd
            position: line.livePosition
            color: line.activeColor
            dim: 0.3
            reduceMotion: line.reduceMotion
        }
    }

    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: line.seekRequested(line.index)
    }
}
