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

    readonly property real progress: position < 0 ? 0
        : Math.max(0, Math.min(1, (position - start) / Math.max(0.05, duration)))
    readonly property string glyphs: text.replace(/\s+$/, "")
    readonly property string trailing: text.substring(glyphs.length)
    readonly property bool stretched: !reduceMotion && duration >= 0.95 && glyphs.length > 0 && glyphs.length <= 14
    readonly property real lift: font.pixelSize * 0.03
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
                        readonly property real slot: root.progress * root.glyphs.length - index
                        // Local 0..1 progress of this letter's rise.
                        readonly property real local: Math.max(0, Math.min(1, (slot + 0.7) / 1.7))
                        readonly property real lit: Math.max(0, Math.min(1, slot + 0.5))

                        text: root.glyphs.charAt(index)
                        font: root.font
                        color: root.color
                        opacity: root.dim + (1 - root.dim) * lit
                        renderType: Text.QtRendering
                        transformOrigin: Item.Bottom
                        y: -root.lift * (0.9 * Math.sin(Math.PI * local) + 0.75 * local)
                        scale: 1 + 0.04 * Math.sin(Math.PI * local)
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
