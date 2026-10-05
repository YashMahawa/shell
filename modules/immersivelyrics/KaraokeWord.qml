pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

// One timed word of the active line.
//
// Ordinary words get a soft-edged highlight sweep (karaoke.frag) and float up
// slightly as they are sung. Stretched notes — held long enough to notice —
// are drawn per character: each letter lights, rises and settles in turn, and
// the word glows while it is held, as Apple Music does.
Item {
    id: root

    required property string text
    required property real start
    required property real duration
    // Seconds; negative when this word's line is not the active one.
    property real position: -1
    property font font
    property real dim: 0.36
    property color color: "white"
    property bool reduceMotion: false

    // Flow timing from KaraokeRows: the sweep spans `flowDuration` (the word
    // plus any short gap after it) and follows a monotone Hermite curve with
    // entry/exit speeds `m0`/`m1`, so pace changes smoothly between words.
    property real flowDuration: duration
    property real m0: 1
    property real m1: 1

    // Not yet reached (or not the active line): nothing lights or moves.
    readonly property bool started: position >= 0 && position >= start
    readonly property real progress: {
        if (!started)
            return 0;
        const u = Math.max(0, Math.min(1, (position - start) / Math.max(0.05, flowDuration)));
        const u2 = u * u;
        const u3 = u2 * u;
        const p = (u3 - 2 * u2 + u) * m0 + (3 * u2 - 2 * u3) + (u3 - u2) * m1;
        return Math.max(0, Math.min(1, p));
    }
    readonly property string glyphs: text.replace(/\s+$/, "")
    readonly property string trailing: text.substring(glyphs.length)
    readonly property bool stretched: !reduceMotion && duration >= 0.95 && glyphs.length > 0 && glyphs.length <= 14
    readonly property real lift: font.pixelSize * 0.037
    readonly property real eased: 1 - Math.pow(1 - progress, 3)

    implicitWidth: measure.advanceWidth
    implicitHeight: lineMetrics.height

    TextMetrics {
        id: measure

        font: root.font
        text: root.text
    }

    FontMetrics {
        id: lineMetrics

        font: root.font
    }

    Loader {
        anchors.fill: parent
        active: !root.stretched
        sourceComponent: Item {
            Text {
                id: label

                text: root.text
                font: root.font
                color: root.color
                renderType: Text.QtRendering
            }

            ShaderEffect {
                readonly property var source: ShaderEffectSource {
                    sourceItem: label
                    hideSource: true
                    smooth: true
                }
                readonly property real progress: root.progress
                readonly property real softness: 0.16
                readonly property real dim: root.dim

                width: label.implicitWidth
                height: label.implicitHeight
                y: root.reduceMotion ? 0 : -root.lift * root.eased
                fragmentShader: Qt.resolvedUrl("../../assets/shaders/karaoke.frag.qsb")
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.stretched
        sourceComponent: Item {
            id: stretch

            // Glow swells while the note is held and fades as it resolves.
            readonly property real glow: root.progress > 0 && root.progress < 1
                ? Math.pow(Math.sin(Math.PI * Math.min(1, root.progress * 1.15)), 0.8) : 0

            Row {
                id: letters

                y: 0
                layer.enabled: stretch.glow > 0.01
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: root.color
                    shadowBlur: 1
                    shadowOpacity: 0.7 * stretch.glow
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    blurMax: 28
                    autoPaddingEnabled: true
                }

                Repeater {
                    model: root.glyphs.length

                    Text {
                        id: letter

                        required property int index
                        // Each letter owns one slice of the word's duration.
                        readonly property real slot: root.progress * root.glyphs.length - index
                        // Local 0..1 progress of this letter's rise.
                        // A wave travels through the word: the letter being sung crests
                        // and its neighbours rise a little with it.
                        readonly property real head: root.progress * root.glyphs.length
                        readonly property real bump: root.started ? Math.exp(-Math.pow(index + 0.5 - head, 2) / 1.1) : 0
                        readonly property real envelope: Math.min(1, head * 1.5) * Math.min(1, (root.glyphs.length - head) * 1.5)
                        readonly property real wave: bump * envelope
                        readonly property real settled: root.started ? Math.max(0, Math.min(1, slot)) : 0
                        readonly property real lit: root.started ? Math.max(0, Math.min(1, slot)) : 0

                        text: root.glyphs.charAt(index)
                        font: root.font
                        color: root.color
                        opacity: root.dim + (1 - root.dim) * lit
                        renderType: Text.QtRendering
                        transformOrigin: Item.Bottom
                        // Settles at the same lift as plain words once sung.
                        y: -root.lift * (0.5 * wave + settled)
                        scale: 1 + 0.03 * wave
                    }
                }

                Text {
                    text: root.trailing
                    font: root.font
                    color: "transparent"
                }
            }
        }
    }
}
