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

    // Continuous flow: short gaps between words are absorbed into the earlier
    // word, and each word's sweep is a monotone Hermite curve whose speed at
    // its edges is shared with its neighbours, so the highlight changes pace
    // smoothly instead of stopping and starting. Real pauses (>= 0.35 s) still
    // ease into a rest, as the singer does.
    readonly property var flowGroups: {
        metrics.height;
        metrics.font;
        const pause = 0.35;
        const flat = [];
        for (const group of groups)
            for (const syllable of group)
                flat.push(syllable);
        const info = flat.map(syl => ({
            w: Math.max(1, metrics.advanceWidth(String(syl.text || "").replace(/\s+$/, ""))),
            t: Number(syl.time) || 0,
            d: Math.max(0.05, Number(syl.duration) || 0)
        }));
        const n = info.length;
        for (let i = 0; i < n; i++) {
            const cur = info[i];
            const next = info[i + 1];
            const gap = next ? next.t - (cur.t + cur.d) : 0;
            cur.pauseAfter = !next || gap >= pause;
            cur.eff = next && gap > 0 && gap < pause ? cur.d + gap
                : next && gap < 0 ? Math.max(0.05, Math.min(cur.d, next.t - cur.t)) : cur.d;
            cur.speed = cur.w / cur.eff;
        }
        const clamp = v => Math.max(0.15, Math.min(2.6, v));
        for (let i = 0; i < n; i++) {
            const cur = info[i];
            const prev = info[i - 1];
            const next = info[i + 1];
            cur.m0 = !prev ? 0.8 : prev.pauseAfter ? 0.75 : clamp(Math.sqrt(prev.speed * cur.speed) * cur.eff / cur.w);
            cur.m1 = cur.pauseAfter ? 0.55 : clamp(Math.sqrt(cur.speed * next.speed) * cur.eff / cur.w);
        }
        let k = 0;
        return groups.map(group => group.map(syl => {
            const f = info[k++];
            return { time: f.t, duration: f.d, text: syl.text, flow: f.eff, m0: f.m0, m1: f.m1 };
        }));
    }

    readonly property var rows: {
        // advanceWidth() is a method call, which bindings do not track; depend
        // on the metrics explicitly so rows re-flow once the font is applied.
        metrics.height;
        metrics.font;
        const out = [];
        let row = [];
        let used = 0;
        for (const group of flowGroups) {
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
                                flowDuration: Number(modelData.flow || modelData.duration || 0)
                                m0: Number(modelData.m0 ?? 1)
                                m1: Number(modelData.m1 ?? 1)
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
