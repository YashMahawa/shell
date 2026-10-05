.pragma library

// Lyric provider endpoints and parsers, modelled on BitChord's LyricsRepository.
//
// Every parser returns an array of normalised lines (all times in ms):
//   { time, duration, text, syllabus: [{ time, duration, text }],
//     agent: "start" | "end", bg: null | { text, syllabus } }
// `syllabus` is empty for line-synced lyrics.
//
// Providers are listed in BitChord's default priority order. The service races
// them in parallel and keeps the highest-ranked word-synced result, falling
// back to the highest-ranked line-synced one.

var providers = [
    { id: "bini", name: "BiniLyrics", detail: "Apple Music lyrics matched by recording" },
    { id: "betterlyrics", name: "BetterLyrics", detail: "Apple Music word-synced lyrics" },
    { id: "portato", name: "BetterLyrics Portato", detail: "QQ Music karaoke timings" },
    { id: "paxsenix-apple", name: "PaxSenix", detail: "Apple Music lyrics via PaxSenix" },
    { id: "lyricsplus", name: "LyricsPlus", detail: "Apple Music, QQ Music and Musixmatch" },
    { id: "lrcmux", name: "LrcMux", detail: "Aggregated word-synced lyrics" },
    { id: "simpmusic", name: "SimpMusic", detail: "YouTube Music rich-synced lyrics" },
    { id: "unison", name: "Unison", detail: "Community lyrics" },
    { id: "youtube", name: "YouTube captions", detail: "Captions from the music video" },
    { id: "kugou", name: "KuGou", detail: "Line-synced lyrics" },
    { id: "lrclib", name: "LRCLIB", detail: "Line-synced lyrics" },
    { id: "musixmatch", name: "Musixmatch", detail: "Musixmatch rich sync via PaxSenix" }
];

var lyricsPlusHosts = [
    "https://lyricsplus.prjktla.my.id",
    "https://lyricsplus.atomix.one",
    "https://lyricsplus.binimum.org",
    "https://lyricsplus.prjktla.workers.dev",
    "https://lyricsplus-seven.vercel.app",
    "https://lyrics-plus-backend.vercel.app"
];

function rankOf(id) {
    for (var i = 0; i < providers.length; i++)
        if (providers[i].id === id)
            return i;
    return providers.length;
}

function providerFor(id) {
    for (var i = 0; i < providers.length; i++)
        if (providers[i].id === id)
            return providers[i];
    return null;
}

function query(params) {
    var parts = [];
    for (var key in params) {
        var value = params[key];
        if (value === undefined || value === null || value === "" || value === 0)
            continue;
        parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(value)));
    }
    return parts.join("&");
}

// ---- search-term clean-up -------------------------------------------------

function searchTitle(title) {
    return String(title || "")
        .replace(/\s*[\[(](official\s+)?(music\s+)?(video|audio|lyrics?|visuali[sz]er|mv|hd|4k)[^\])]*[\])]/ig, "")
        .replace(/\s*[\[(](feat|ft)\.?[^\])]*[\])]/ig, "")
        .replace(/\s+-\s+topic$/i, "")
        .trim();
}

function searchArtist(artist) {
    return String(artist || "")
        .replace(/\s+-\s+topic$/i, "")
        .replace(/\s*VEVO$/i, "")
        .trim();
}

// ---- small helpers ----------------------------------------------------------

function decodeEntities(text) {
    return String(text)
        .replace(/&lt;/g, "<").replace(/&gt;/g, ">")
        .replace(/&quot;/g, "\"").replace(/&apos;|&#39;/g, "'")
        .replace(/&#x([0-9a-f]+);/gi, function (m, n) { return String.fromCharCode(parseInt(n, 16)); })
        .replace(/&#(\d+);/g, function (m, n) { return String.fromCharCode(Number(n)); })
        .replace(/&amp;/g, "&");
}

function attr(tag, name) {
    var re = new RegExp("(?:^|\\s)" + name.replace(/[:.]/g, "\\$&") + "=\"([^\"]*)\"");
    var m = re.exec(tag);
    return m ? m[1] : "";
}

function parseClock(value) {
    var text = String(value || "").trim().replace(/s$/, "");
    if (!text)
        return NaN;
    var parts = text.split(":");
    var total = 0;
    for (var i = 0; i < parts.length; i++)
        total = total * 60 + Number(parts[i]);
    return total * 1000;
}

function joinSyllables(syllables) {
    var text = "";
    for (var i = 0; i < syllables.length; i++)
        text += syllables[i].text;
    return text.replace(/\s+/g, " ").trim();
}

function finishLine(line) {
    if (!line.duration && line.syllabus.length) {
        var last = line.syllabus[line.syllabus.length - 1];
        line.duration = Math.max(0, last.time + last.duration - line.time);
    }
    return line;
}

// Repairs word timestamps so no word can light before it is sung: missing,
// zero, out-of-range or out-of-order times are interpolated between their
// valid neighbours (weighted by text length), starts are made monotonic and
// durations are clamped so a word ends no later than the next one starts.
function sanitizeSyllables(syllables, lineStart, lineEnd) {
    var n = syllables.length;
    if (!n)
        return syllables;
    var lo = lineStart - 1000;
    var hi = lineEnd > lineStart ? lineEnd + 1500 : Infinity;
    var valid = [];
    for (var i = 0; i < n; i++) {
        var t = Number(syllables[i].time);
        valid.push(isFinite(t) && t > 0 && t >= lo && t <= hi);
    }
    // Times must also increase; drop any that jump backwards.
    var last = -Infinity;
    for (var j = 0; j < n; j++) {
        if (!valid[j])
            continue;
        if (syllables[j].time + 1 < last)
            valid[j] = false;
        else
            last = syllables[j].time;
    }
    var k = 0;
    while (k < n) {
        if (valid[k]) {
            k++;
            continue;
        }
        var startIdx = k;
        while (k < n && !valid[k])
            k++;
        var prev = startIdx > 0 ? syllables[startIdx - 1] : null;
        var from = prev ? prev.time + Math.max(0, prev.duration || 0) : lineStart;
        var to = k < n ? syllables[k].time : (lineEnd > from ? lineEnd : from + 400 * (k - startIdx));
        var weights = 0;
        for (var a = startIdx; a < k; a++)
            weights += Math.max(1, String(syllables[a].text || "").trim().length);
        var cursor = from;
        for (var b = startIdx; b < k; b++) {
            var share = Math.max(1, String(syllables[b].text || "").trim().length) / weights * Math.max(0, to - from);
            syllables[b].time = cursor;
            syllables[b].duration = share;
            cursor += share;
        }
    }
    for (var m = 0; m < n; m++) {
        var s = syllables[m];
        if (m > 0 && s.time < syllables[m - 1].time)
            s.time = syllables[m - 1].time;
        var next = m + 1 < n ? syllables[m + 1].time : (lineEnd > s.time ? lineEnd : s.time + 600);
        var d = Number(s.duration);
        if (!isFinite(d) || d <= 0)
            d = next - s.time;
        s.duration = Math.max(60, Math.min(d, Math.max(60, next - s.time)));
    }
    return syllables;
}

// Fills in missing line durations from the next stamp (blank LRC stamps mark
// instrumental breaks, so they count) and then drops empty lines. A line-synced
// line that would otherwise run across a long break is capped at a plausible
// sung length, so the break can show interlude dots.
function settle(lines) {
    var all = lines.filter(function (line) { return !!line; });
    all.sort(function (a, b) { return a.time - b.time; });
    for (var j = 0; j < all.length; j++) {
        if (!(all[j].duration > 0)) {
            var next = all[j + 1];
            var span = next ? Math.max(0, next.time - all[j].time) : 4000;
            if (!all[j].syllabus.length && span > 9000) {
                var chars = String(all[j].text || "").length;
                span = Math.min(span, Math.max(2500, Math.min(7000, 1500 + chars * 260)));
            }
            all[j].duration = span;
        }
    }
    for (var q = 0; q < all.length; q++) {
        var ln = all[q];
        var end = ln.time + (ln.duration || 0);
        if (ln.syllabus && ln.syllabus.length)
            sanitizeSyllables(ln.syllabus, ln.time, end);
        if (ln.bg && ln.bg.syllabus && ln.bg.syllabus.length)
            sanitizeSyllables(ln.bg.syllabus, ln.bg.syllabus[0].time > 0 ? Math.min(ln.time, ln.bg.syllabus[0].time) : ln.time, end + 1500);
    }
    return all.filter(function (line) { return !!(line.text || (line.bg && line.bg.text)); });
}

function hasWordTiming(lines) {
    for (var i = 0; i < (lines || []).length; i++) {
        var syllables = lines[i].syllabus || [];
        for (var j = 0; j < syllables.length; j++)
            if (Number(syllables[j].duration || 0) > 0)
                return true;
    }
    return false;
}

function hasLineTiming(lines) {
    for (var i = 0; i < (lines || []).length; i++)
        if (Number(lines[i].time || 0) > 0 && String(lines[i].text || "").trim())
            return true;
    return false;
}

// ---- duet alignment (BitChord LyricAlignments) -----------------------------

// Sides alternate whenever the voice changes, so a three-way song still reads
// as a conversation. Group lines stay on the leading side. A song that ends up
// almost entirely on the trailing side is flipped back.
function applyAlignments(lines, singers, types) {
    var left = true;
    var lastVoice = null;
    var rightward = 0;
    var placed = 0;
    var sides = [];
    for (var i = 0; i < lines.length; i++) {
        var singer = singers[i];
        if (!singer) {
            sides.push("start");
            continue;
        }
        var type = types[singer] || (singer === "v1000" ? "group" : singer === "v2000" ? "other" : "person");
        placed++;
        if (type === "group") {
            sides.push("start");
            continue;
        }
        if (lastVoice === null)
            left = type !== "other";
        else if (singer !== lastVoice)
            left = !left;
        lastVoice = singer;
        if (!left)
            rightward++;
        sides.push(left ? "start" : "end");
    }
    var flip = placed > 0 && rightward / placed >= 0.85;
    for (var k = 0; k < lines.length; k++)
        lines[k].agent = flip ? (sides[k] === "start" ? "end" : "start") : sides[k];
    return lines;
}

// ---- background vocals (BitChord BackgroundVocals) --------------------------

// Providers other than Apple TTML write the answering vocal into the line as a
// trailing bracket: "I'm foolishly patient (Foolishly patient)". Split it out so
// it renders as a smaller line beneath the lead with its own timing.
function splitTrailingBracket(line) {
    if (line.bg || !line.text)
        return line;
    var text = line.text;
    if (text.charAt(text.length - 1) !== ")")
        return line;
    var depth = 0;
    var open = -1;
    for (var i = text.length - 1; i >= 0; i--) {
        var ch = text.charAt(i);
        if (ch === ")")
            depth++;
        else if (ch === "(") {
            depth--;
            if (depth === 0) {
                open = i;
                break;
            }
        }
    }
    if (open <= 0)
        return line;
    var lead = text.substring(0, open).trim();
    var backing = text.substring(open).trim();
    if (!lead || !/[\p{L}\p{N}]/u.test(backing))
        return line;

    if (!line.syllabus.length) {
        line.text = lead;
        line.bg = { text: backing, syllabus: [] };
        return line;
    }

    var at = 0;
    for (var s = 0; s < line.syllabus.length; s++) {
        var piece = line.syllabus[s].text;
        var trimmed = piece.replace(/^\s+/, "");
        at += piece.length - trimmed.length;
        if (trimmed.charAt(0) === "(" && at >= lead.length - 1) {
            if (s === 0)
                return line;
            var leadSyllables = line.syllabus.slice(0, s);
            var backingSyllables = line.syllabus.slice(s);
            line.syllabus = leadSyllables;
            line.text = joinSyllables(leadSyllables) || lead;
            line.bg = { text: joinSyllables(backingSyllables) || backing, syllabus: backingSyllables };
            return line;
        }
        at += trimmed.length;
    }
    return line;
}

// ---- Apple TTML (BetterLyrics, BiniLyrics, Unison, PaxSenix) ----------------

function parseTtml(ttml) {
    var doc = String(ttml || "");
    if (doc.indexOf("<tt") < 0)
        return [];

    var types = {};
    var agentRe = /<ttm:agent\b([^>]*)>/g;
    var am;
    while ((am = agentRe.exec(doc)) !== null)
        types[attr(am[1], "xml:id")] = attr(am[1], "type");

    var lines = [];
    var singers = [];
    var pRe = /<p\b([^>]*)>([\s\S]*?)<\/p>/g;
    var pm;
    while ((pm = pRe.exec(doc)) !== null) {
        var pAttrs = pm[1];
        var begin = parseClock(attr(pAttrs, "begin"));
        var end = parseClock(attr(pAttrs, "end"));
        var main = [];
        var backing = [];
        var plain = "";
        var stack = [];
        var tokenRe = /<span\b([^>]*)>|<\/span>|<br\s*\/?>|<[^>]+>|([^<]+)/g;
        var tm;
        while ((tm = tokenRe.exec(pm[2])) !== null) {
            if (tm[0].indexOf("<span") === 0) {
                stack.push(tm[1]);
            } else if (tm[0] === "</span>") {
                stack.pop();
            } else if (tm[2] !== undefined) {
                var raw = decodeEntities(tm[2]);
                var inBg = false;
                for (var s = 0; s < stack.length; s++)
                    if (attr(stack[s], "ttm:role") === "x-bg")
                        inBg = true;
                var target = inBg ? backing : main;
                var top = stack.length ? stack[stack.length - 1] : "";
                var spanBegin = parseClock(attr(top, "begin"));
                if (top && !isNaN(spanBegin)) {
                    var spanEnd = parseClock(attr(top, "end"));
                    target.push({
                        time: spanBegin,
                        duration: Math.max(0, (isNaN(spanEnd) ? spanBegin : spanEnd) - spanBegin),
                        text: raw.replace(/\s+/g, " ")
                    });
                } else if (/^\s+$/.test(raw)) {
                    // Whitespace between spans marks a word boundary.
                    if (target.length)
                        target[target.length - 1].text += " ";
                } else {
                    plain += raw;
                }
            }
        }

        var line = {
            time: isNaN(begin) ? (main.length ? main[0].time : 0) : begin,
            duration: !isNaN(begin) && !isNaN(end) ? Math.max(0, end - begin) : 0,
            text: main.length ? joinSyllables(main) : plain.replace(/\s+/g, " ").trim(),
            syllabus: main,
            agent: "start",
            bg: backing.length ? { text: joinSyllables(backing), syllabus: backing } : null
        };
        if (main.length)
            line.time = Math.min(line.time, main[0].time);
        lines.push(finishLine(line));
        singers.push(attr(pAttrs, "ttm:agent"));
    }
    applyAlignments(lines, singers, types);
    return settle(lines);
}

// ---- LyricsPlus / LrcMux (KPoe JSON) ----------------------------------------

function parseKpoe(response) {
    var rows = response && Array.isArray(response.lyrics) ? response.lyrics : [];
    var types = {};
    var agents = response && response.metadata && response.metadata.agents || {};
    for (var key in agents)
        types[key] = agents[key].type || "person";

    var lines = [];
    var singers = [];
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i];
        var main = [];
        var backing = [];
        var raw = Array.isArray(row.syllabus) ? row.syllabus : [];
        for (var j = 0; j < raw.length; j++) {
            var syl = {
                time: Number(raw[j].time || 0),
                duration: Number(raw[j].duration || 0),
                text: String(raw[j].text || "")
            };
            (raw[j].isBackground ? backing : main).push(syl);
        }
        var line = {
            time: Number(row.time || 0),
            duration: Number(row.duration || 0),
            text: main.length ? joinSyllables(main) : String(row.text || "").trim(),
            syllabus: main,
            agent: "start",
            bg: backing.length ? { text: joinSyllables(backing), syllabus: backing } : null
        };
        if (main.length)
            line.time = Math.min(line.time, main[0].time);
        lines.push(splitTrailingBracket(finishLine(line)));
        var element = row.element;
        singers.push(element && !Array.isArray(element) ? element.singer || "" : "");
    }
    applyAlignments(lines, singers, types);
    return settle(lines);
}

// ---- LRC (LRCLIB, KuGou, SimpMusic, Unison) ---------------------------------

// Handles standard LRC, multiple stamps per line and enhanced word tags
// (`<mm:ss.xx>word`). Credits headers that KuGou prepends are dropped.
function parseLrc(text) {
    var source = String(text || "");
    var offsetMatch = /\[offset:\s*([+-]?\d+)\s*\]/i.exec(source);
    var offset = offsetMatch ? Number(offsetMatch[1]) : 0;
    var stampRe = /\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]/g;
    var lines = [];
    var rows = source.split(/\r?\n/);
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i];
        var stamps = [];
        var sm;
        stampRe.lastIndex = 0;
        var lastIndex = 0;
        while ((sm = stampRe.exec(row)) !== null) {
            if (sm.index !== lastIndex)
                break;
            stamps.push(Number(sm[1]) * 60000 + Number(sm[2].replace(":", ".")) * 1000);
            lastIndex = stampRe.lastIndex;
        }
        if (!stamps.length)
            continue;
        var body = row.substring(lastIndex);
        var syllables = [];
        var wordRe = /<(\d{1,3}):(\d{1,2}(?:\.\d{1,3})?)>([^<]*)/g;
        var wm;
        while ((wm = wordRe.exec(body)) !== null)
            syllables.push({ time: Number(wm[1]) * 60000 + Number(wm[2]) * 1000 - offset, duration: 0, text: wm[3] });
        for (var w = 0; w < syllables.length; w++) {
            var next = syllables[w + 1];
            syllables[w].duration = next ? Math.max(0, next.time - syllables[w].time) : 600;
        }
        syllables = syllables.filter(function (s) { return s.text.length > 0; });
        var plainText = (syllables.length ? joinSyllables(syllables) : body).replace(/\s+/g, " ").trim();
        if (/^(作词|作曲|编曲|制作|词|曲)\s*[:：]/.test(plainText))
            continue;
        for (var s = 0; s < stamps.length; s++) {
            lines.push(splitTrailingBracket(finishLine({
                time: stamps[s] - offset,
                duration: 0,
                text: plainText,
                syllabus: syllables,
                agent: "start",
                bg: null
            })));
        }
    }
    return settle(lines);
}

// ---- Musixmatch rich sync via PaxSenix ---------------------------------------

function parseMusixmatch(res) {
    var rich = res && (res.richsync || (res.data && res.data.richsync) || (res.lyrics && res.lyrics.richsync));
    if (typeof rich === "string") {
        try {
            rich = JSON.parse(rich);
        } catch (e) {
            rich = undefined;
        }
    }
    var rows = Array.isArray(rich) ? rich : res && res.lyrics;
    if (!Array.isArray(rows))
        rows = (res && res.data && res.data.lyrics && res.data.lyrics.lines) || (res && res.lines) || [];
    var lines = [];
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i];
        var rich = row.ts !== undefined;
        var start = rich ? Number(row.ts || 0) * 1000 : Number(row.time !== undefined ? row.time : (row.startTimeMs || row.start || 0));
        var end = rich ? Number(row.te || row.ts || 0) * 1000 : Number(row.endTimeMs || row.end || 0);
        var words = Array.isArray(row.syllabus) ? row.syllabus : Array.isArray(row.l) ? row.l : Array.isArray(row.words) ? row.words : [];
        var syllables = [];
        for (var j = 0; j < words.length; j++) {
            var word = words[j];
            var wordStart;
            var wordEnd;
            if (rich && word.o !== undefined) {
                wordStart = start + Number(word.o || 0) * 1000;
                var nextWord = words[j + 1];
                wordEnd = nextWord && nextWord.o !== undefined ? start + Number(nextWord.o) * 1000 : end;
            } else {
                wordStart = Number(word.time !== undefined ? word.time : (word.startTimeMs || word.start || 0));
                wordEnd = Number(word.endTimeMs || word.end || 0);
            }
            var duration = Number(word.duration !== undefined ? word.duration : Math.max(0, wordEnd - wordStart));
            syllables.push({ time: wordStart, duration: duration, text: String(word.text !== undefined ? word.text : (word.c !== undefined ? word.c : "")) });
        }
        syllables = syllables.filter(function (s) { return s.text.length > 0; });
        lines.push(splitTrailingBracket(finishLine({
            time: start,
            duration: Math.max(0, end - start),
            text: syllables.length ? joinSyllables(syllables) : String(row.text || row.x || "").trim(),
            syllabus: syllables,
            agent: "start",
            bg: null
        })));
    }
    return settle(lines);
}

// Lines shaped like the legacy cache / YouTube helper output.
function parseLegacy(rows) {
    var lines = [];
    for (var i = 0; i < (rows || []).length; i++) {
        var row = rows[i];
        var syllables = [];
        var raw = row.syllabus || [];
        for (var j = 0; j < raw.length; j++)
            syllables.push({ time: Number(raw[j].time || 0), duration: Number(raw[j].duration || 0), text: String(raw[j].text || "") });
        lines.push(finishLine({
            time: Number(row.time || 0),
            duration: Number(row.duration || 0),
            text: String(row.text || "").trim(),
            syllabus: syllables,
            agent: row.agent === "end" ? "end" : "start",
            bg: row.bg || null
        }));
    }
    return settle(lines);
}

// ---- URLs -------------------------------------------------------------------

function seconds(durationMs) {
    return durationMs > 0 ? Math.round(durationMs / 1000) : 0;
}

function biniSearchUrl(t) {
    return "https://lyrics-api.binimum.org/?" + query({ track: t.title, artist: t.artist, album: t.album, duration: seconds(t.duration) });
}

function betterLyricsUrl(t) {
    return "https://lyrics-api.boidu.dev/getLyrics?" + query({ s: t.title, a: t.artist, d: seconds(t.duration), al: t.album });
}

function portatoUrl(t) {
    return "https://lyrics-api.boidu.dev/qq/getLyrics?" + query({ s: t.title, a: t.artist, d: seconds(t.duration), al: t.album });
}

function lyricsPlusUrl(host, t) {
    return host + "/v2/lyrics/get?" + query({ title: t.title, artist: t.artist, duration: seconds(t.duration), album: t.album });
}

function lrcMuxUrl(t) {
    return "https://api.lrcmux.dev/compat/kpoe/v2/lyrics/get?" + query({ title: t.title, artist: t.artist, duration: seconds(t.duration) });
}

function simpMusicUrl(videoId) {
    return "https://api-lyrics.simpmusic.org/v1/" + encodeURIComponent(videoId);
}

function unisonUrl(t) {
    return "https://unison.boidu.dev/lyrics?" + query({ song: t.title, artist: t.artist, album: t.album, duration: seconds(t.duration) });
}

function kugouSearchUrl(t) {
    return "https://lyrics.kugou.com/search?" + query({ ver: 1, man: "yes", client: "pc", keyword: t.artist + " - " + t.title, duration: t.duration > 0 ? Math.round(t.duration) : 0 });
}

function kugouDownloadUrl(id, accessKey) {
    return "https://lyrics.kugou.com/download?" + query({ fmt: "lrc", charset: "utf8", client: "pc", ver: 1, id: id, accesskey: accessKey });
}

function lrclibUrl(t) {
    return "https://lrclib.net/api/get?" + query({ track_name: t.title, artist_name: t.artist, album_name: t.album, duration: seconds(t.duration) });
}

function appleSearchUrl(t) {
    return "https://amp-api.music.apple.com/v1/catalog/us/search?" + query({ term: t.title + " " + t.artist, types: "songs", limit: 10, l: "en-US" });
}

function paxsenixAppleUrl(id) {
    return "https://lyrics.paxsenix.org/apple-music/lyrics?" + query({ id: id, ttml: "true" });
}

function musixmatchUrl(t) {
    var q = (t.title + " " + t.artist).trim();
    return "https://lyrics.paxsenix.org/musixmatch/lyrics?" + query({ type: "word", q: q, t: t.title, a: t.artist, enchanted: "true", alt: "true", parse: "true", v: 2, d: seconds(t.duration) });
}

// ---- matching -----------------------------------------------------------------

function normalise(value) {
    return String(value || "").toLowerCase()
        .replace(/\s*[\[(].*?[\])]/g, "")
        .replace(/[^\p{L}\p{N}]+/gu, " ")
        .trim();
}

function textScore(candidate, wanted, exact, partial) {
    var a = normalise(candidate);
    var b = normalise(wanted);
    if (!a || !b)
        return 0;
    if (a === b)
        return exact;
    if (a.indexOf(b) >= 0 || b.indexOf(a) >= 0)
        return partial;
    return 0;
}

// PaxSenix-style candidate scoring for catalogue search hits.
function bestAppleSong(response, t) {
    var hits = response && response.results && response.results.songs && response.results.songs.data || [];
    var best = null;
    var bestScore = -1;
    for (var i = 0; i < hits.length; i++) {
        var a = hits[i].attributes || {};
        var score = textScore(a.name, t.title, 20, 10) + textScore(a.artistName, t.artist, 15, 5);
        if (t.duration > 0 && a.durationInMillis) {
            var delta = Math.abs(a.durationInMillis - t.duration * 1000);
            score += delta < 3000 ? 10 : delta < 10000 ? 5 : 0;
        }
        if (score > bestScore) {
            best = hits[i];
            bestScore = score;
        }
    }
    return bestScore >= 10 ? best : null;
}

function bestKugouCandidate(response, t) {
    var candidates = response && response.candidates || [];
    var best = null;
    var bestDelta = Infinity;
    for (var i = 0; i < candidates.length; i++) {
        var c = candidates[i];
        var delta = t.duration > 0 && c.duration ? Math.abs(c.duration - t.duration * 1000) : 0;
        if (delta > 8000)
            continue;
        if (delta < bestDelta) {
            best = c;
            bestDelta = delta;
        }
    }
    return best;
}

function decodeBase64Utf8(data) {
    try {
        var binary = Qt.atob(String(data || ""));
        return decodeURIComponent(escape(binary));
    } catch (e) {
        return "";
    }
}
