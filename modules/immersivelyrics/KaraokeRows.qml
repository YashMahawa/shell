pragma ComponentBehavior: Bound

import QtQuick

// Word-timed lyric text broken into rows that can be aligned to either side,
// which Flow cannot do. Rows are filled greedily by word, matching how the
// plain Text version of the same line wraps, so heights agree.
Item {
    id: root

    // Word groups: arrays of syllables ({ time, duration, text }).
    required property var groups
    required property font font
    required property real maxWidth
    property bool alignEnd: false
    property real position: -1
    property color color: "white"
    property real dim: 0.36
    property bool reduceMotion: false

    readonly property var rows: {
        // advanceWidth() is a method call, which bindings do not track; depend
        // on the metrics explicitly so rows re-flow once the font is applied.
        metrics.height;
        metrics.font;
        const out = [];
        let row = [];
        let used = 0;
        for (const group of groups) {
            const text = group.map(s => s.text).join("");
            const width = metrics.advanceWidth(text);
            const ink = metrics.advanceWidth(text.replace(/\s+$/, ""));
            if (row.length && used + ink > maxWidth) {
                out.push(row);
                row = [];
                used = 0;
            }
            row.push(group);
            used += width;
        }
        if (row.length)
            out.push(row);
        return out;
    }

    implicitWidth: maxWidth
    implicitHeight: column.implicitHeight

    FontMetrics {
        id: metrics

        font: root.font
    }

    Column {
        id: column

        width: root.maxWidth

        Repeater {
            model: root.rows

            Row {
                id: row

                required property var modelData
                readonly property string lastText: {
                    const last = modelData[modelData.length - 1] ?? [];
                    return last.length ? last[last.length - 1].text : "";
                }

                // Right-aligned rows ignore the trailing space of their last word.
                x: root.alignEnd ? root.maxWidth - implicitWidth + (/\s$/.test(lastText) ? metrics.advanceWidth(" ") : 0) : 0

                Repeater {
                    model: row.modelData

                    Row {
                        id: word

                        required property var modelData

                        Repeater {
                            model: word.modelData

                            KaraokeWord {
                                required property var modelData

                                text: modelData.text
                                start: Number(modelData.time || 0)
                                duration: Number(modelData.duration || 0)
                                position: root.position
                                font: root.font
                                color: root.color
                                dim: root.dim
                                reduceMotion: root.reduceMotion
                            }
                        }
                    }
                }
            }
        }
    }
}
