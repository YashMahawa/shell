pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property string lineText
    required property string syllabus
    required property real position
    property font lyricFont
    property color waitingColor: "#69727e"
    property color activeColor: "#b7c0cc"
    property var segments: _segmentsFor(lineText, syllabus)

    implicitHeight: flow.implicitHeight

    function _segmentsFor(text: string, encoded: string): var {
        const base = String(text || ". . .");
        let syllables = [];
        try {
            syllables = JSON.parse(encoded || "[]");
        } catch (error) {
            syllables = [];
        }
        if (!syllables.length)
            return [{ text: base, timed: false, revealAt: Number.MAX_VALUE }];

        const output = [];
        const lower = base.toLocaleLowerCase();
        let cursor = 0;
        let lastEnd = 0;
        for (const syllable of syllables) {
            const raw = String(syllable.text || "").trim();
            if (!raw)
                continue;
            const match = lower.indexOf(raw.toLocaleLowerCase(), cursor);
            if (match < 0)
                continue;
            const start = Number(syllable.time || 0);
            const duration = Math.max(0.045, Number(syllable.duration || 0.18));
            if (match > cursor)
                output.push({ text: base.slice(cursor, match), timed: false, revealAt: start });
            output.push({
                text: base.slice(match, match + raw.length),
                timed: true,
                start,
                duration
            });
            cursor = match + raw.length;
            lastEnd = start + duration;
        }
        if (!output.length)
            return [{ text: base, timed: false, revealAt: Number.MAX_VALUE }];
        if (cursor < base.length)
            output.push({ text: base.slice(cursor), timed: false, revealAt: lastEnd });
        return output;
    }

    Flow {
        id: flow

        width: root.width
        spacing: 0

        Repeater {
            model: root.segments

            delegate: Item {
                id: segment

                required property var modelData
                readonly property real progress: {
                    if (!modelData.timed)
                        return root.position >= Number(modelData.revealAt) ? 1 : 0;
                    return Math.max(0, Math.min(1, (root.position - Number(modelData.start)) / Number(modelData.duration)));
                }

                width: baseText.implicitWidth
                height: baseText.implicitHeight

                Text {
                    id: baseText

                    text: segment.modelData.text
                    color: root.waitingColor
                    font: root.lyricFont
                    renderType: Text.QtRendering
                    renderTypeQuality: Text.VeryHighRenderTypeQuality
                }

                Item {
                    width: baseText.implicitWidth * segment.progress
                    height: baseText.implicitHeight
                    clip: true

                    Text {
                        text: baseText.text
                        color: root.activeColor
                        opacity: 0.78
                        font: root.lyricFont
                        renderType: Text.QtRendering
                        renderTypeQuality: Text.VeryHighRenderTypeQuality
                    }
                }
            }
        }
    }
}
