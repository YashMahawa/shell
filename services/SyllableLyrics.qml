pragma Singleton

import "../utils/scripts/lrcparser.js" as Lrc
import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.utils

Singleton {
    id: root

    property int currentIndex: -1
    property bool loading: false
    property bool hasSyllables: false
    property int revision: 0
    property int requestId: 0
    property string loadedKey: ""
    property string cachePath: ""
    property bool cacheLoaded: false
    property bool romanizeLyrics: GlobalConfig.services.romanizeLyrics ?? true
    readonly property string preferredBackend: GlobalConfig.services.lyricsBackend ?? "Auto"

    readonly property alias model: lyricsModel
    readonly property bool hasLyrics: lyricsModel.count > 0
    readonly property string cacheDir: `${Paths.state}/lyrics-plus`

    onRomanizeLyricsChanged: {
        root.loadedKey = "";
        root.load();
    }

    onPreferredBackendChanged: {
        root.loadedKey = "";
        root.load();
    }

    function _keyForPlayer(): string {
        const p = Players.active;
        if (!p)
            return "";
        return `${p.trackArtist || ""} - ${p.trackTitle || ""}`;
    }

    function _trackDuration(): int {
        const p = Players.active;
        if (!p)
            return 0;
        if (p.length)
            return Math.floor(p.length);
        const len = p.metadata?.["mpris:length"];
        return len ? Math.floor(len / 1000000) : 0;
    }

    function _cleanText(text: string): string {
        const clean = (text || "").replace(/\u00a0/g, " ");
        return root.romanizeLyrics ? Lrc.transliterate(clean) : clean;
    }

    function _usePaxsenix(): bool {
        const backend = String(root.preferredBackend || "Auto").toLowerCase();
        return backend === "auto" || backend === "paxsenix" || backend === "parsenix";
    }

    function _shellQuote(text: string): string {
        return `'${String(text).replace(/'/g, "'\\''")}'`;
    }

    function _safeCacheName(key: string): string {
        return key.toLowerCase().replace(/[^a-z0-9._-]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 180) || "unknown";
    }

    function _setCachePath(key: string): void {
        root.cachePath = `${root.cacheDir}/${_safeCacheName(`${root.preferredBackend}-${key}`)}.json`;
    }

    function _metadataMatches(meta: var): bool {
        const p = Players.active;
        if (!p || !meta)
            return true;

        function clean(value) {
            return String(value || "").toLowerCase().replace(/\s*\(.*?\)/g, "").replace(/\s*\[.*?\]/g, "").trim();
        }

        const targetTitle = clean(p.trackTitle);
        const targetArtist = clean(p.trackArtist).split(/[&,xX]/)[0].trim();
        const returnedTitle = clean(meta.title);
        const returnedArtist = clean(meta.artist).split(/[&,xX]/)[0].trim();

        if (returnedTitle && targetTitle && returnedTitle !== targetTitle && !returnedTitle.includes(targetTitle) && !targetTitle.includes(returnedTitle))
            return false;
        if (returnedArtist && targetArtist && returnedArtist !== targetArtist && !returnedArtist.includes(targetArtist) && !targetArtist.includes(returnedArtist))
            return false;

        const duration = _trackDuration();
        if (duration > 0 && meta.duration && Math.abs(Number(meta.duration) - duration) > 15)
            return false;

        return true;
    }

    function _setNativeFallback(): void {
        if (root.hasSyllables)
            return;

        lyricsModel.clear();
        const lines = Lyrics.lyrics;
        for (let i = 0; i < lines.length; i++) {
            lyricsModel.append({
                lyricLine: _cleanText(lines[i]) || ". . .",
                time: Lyrics.timeForIndex(i),
                syllabus: "[]"
            });
        }
        root.loading = Lyrics.loading;
        root.currentIndex = Lyrics.indexForTime(Players.active?.position ?? 0);
        root.revision++;
    }

    function _hasTimedSyllables(lines: var): bool {
        if (!lines || lines.length === 0)
            return false;

        for (const line of lines) {
            const syllables = line.syllabus || [];
            if (!syllables.length)
                continue;
            for (const syl of syllables) {
                if (Number(syl.duration || 0) > 0 || Number(syl.time || 0) > 0)
                    return true;
            }
        }
        return false;
    }

    function load(): void {
        loadDebounce.restart();
    }

    function _doLoad(): void {
        const p = Players.active;
        const key = _keyForPlayer();
        if (key && key === root.loadedKey && lyricsModel.count > 0)
            return;

        root.loadedKey = key;
        root.hasSyllables = false;
        root.loading = true;
        root.currentIndex = -1;
        root.requestId++;
        const req = root.requestId;

        if (!p || !p.trackTitle) {
            lyricsModel.clear();
            root.loading = false;
            root.revision++;
            return;
        }

        if (!_usePaxsenix()) {
            root.loading = Lyrics.loading;
            _setNativeFallback();
            return;
        }

        root.cacheLoaded = false;
        _setCachePath(key);
        cacheFile.reload();
        cacheDelay.requestId = req;
        cacheDelay.restart();
    }

    function _fetchOnline(req: int): void {
        const p = Players.active;
        if (!p || !p.trackTitle || req !== root.requestId)
            return;

        let url = `https://lyricsplus.prjktla.my.id/v2/lyrics/get?title=${encodeURIComponent(p.trackTitle)}&artist=${encodeURIComponent(p.trackArtist || "")}`;
        const duration = _trackDuration();
        if (duration > 0)
            url += `&duration=${duration}`;

        Requests.get(url, text => {
            if (req !== root.requestId)
                return;

            try {
                const res = JSON.parse(text);
                const meta = res.cachedMeta || res.metadata || {};
                const lines = res.lyrics || [];
                if (!_metadataMatches(meta) || !_hasTimedSyllables(lines))
                    throw new Error("Paxsenix result did not provide timed syllables for the current track");

                _loadLines(lines);
                _saveCache(lines);
            } catch (e) {
                root.loading = false;
                _setNativeFallback();
            }
        }, () => {
            if (req !== root.requestId)
                return;
            root.loading = false;
            _setNativeFallback();
        });
    }

    function _loadLines(lines: var): void {
        if (!_hasTimedSyllables(lines)) {
            root.hasSyllables = false;
            root.loading = false;
            _setNativeFallback();
            return;
        }

        lyricsModel.clear();
        let timedSyllableCount = 0;
        for (const line of lines) {
            const syllables = [];
            for (const syl of line.syllabus || []) {
                if (Number(syl.duration || 0) > 0 || Number(syl.time || 0) > 0)
                    timedSyllableCount++;
                syllables.push({
                    time: Number(syl.time || 0) / 1000,
                    duration: Number(syl.duration || 0) / 1000,
                    text: _cleanText(syl.text || "")
                });
            }

            lyricsModel.append({
                lyricLine: _cleanText(line.text || ""),
                time: Number(line.time || 0) / 1000,
                syllabus: JSON.stringify(syllables)
            });
        }

        root.hasSyllables = lyricsModel.count > 0 && timedSyllableCount > 0;
        root.loading = false;
        root.revision++;
        updatePosition();
    }

    function _saveCache(lines: var): void {
        const payload = JSON.stringify({
            key: root.loadedKey,
            provider: "Paxsenix",
            romanized: root.romanizeLyrics,
            lyrics: lines
        });
        saveCache.command = ["sh", "-c", `mkdir -p ${_shellQuote(root.cacheDir)} && printf %s ${_shellQuote(payload)} > ${_shellQuote(root.cachePath)}`];
        saveCache.running = true;
    }

    function indexForTime(time: real): int {
        if (!root.hasSyllables)
            return Lyrics.indexForTime(time);

        for (let i = lyricsModel.count - 1; i >= 0; i--) {
            if (time >= lyricsModel.get(i).time - 0.1)
                return i;
        }
        return -1;
    }

    function timeForIndex(index: int): real {
        if (index < 0)
            return 0;
        if (!root.hasSyllables)
            return Lyrics.timeForIndex(index);
        return lyricsModel.get(index)?.time ?? 0;
    }

    function updatePosition(): void {
        const next = indexForTime(Players.active?.position ?? 0);
        if (next !== root.currentIndex)
            root.currentIndex = next;
    }

    function jumpTo(index: int): void {
        const p = Players.active;
        if (p)
            p.position = timeForIndex(index) + 0.01;
    }

    ListModel {
        id: lyricsModel
    }

    Timer {
        interval: 500
        running: root.hasLyrics && !!Players.active
        repeat: true
        onTriggered: root.updatePosition()
    }

    Timer {
        id: loadDebounce

        interval: 120
        repeat: false
        onTriggered: root._doLoad()
    }

    Timer {
        id: cacheDelay

        property int requestId: -1

        interval: 120
        repeat: false
        onTriggered: {
            if (requestId === root.requestId && !root.cacheLoaded)
                root._fetchOnline(requestId);
        }
    }

    FileView {
        id: cacheFile

        path: root.cachePath
        printErrors: false
        onLoaded: {
            if (!root.cachePath)
                return;
            try {
                const cached = JSON.parse(text());
                if (cached.key === root.loadedKey && cached.provider === "Paxsenix" && _hasTimedSyllables(cached.lyrics)) {
                    root.cacheLoaded = true;
                    root._loadLines(cached.lyrics);
                }
            } catch (e) {
                root.cacheLoaded = false;
            }
        }
    }

    Process {
        id: saveCache
    }

    Connections {
        target: Players
        function onActiveChanged(): void {
            root.load();
        }
    }

    Connections {
        target: Players.active
        ignoreUnknownSignals: true
        function onPostTrackChanged(): void {
            root.load();
        }
        function onTrackTitleChanged(): void {
            root.load();
        }
        function onTrackArtistChanged(): void {
            root.load();
        }
    }

    Connections {
        target: Lyrics
        function onLyricsChanged(): void {
            root._setNativeFallback();
        }
        function onLoadingChanged(): void {
            if (!root.hasSyllables)
                root.loading = Lyrics.loading;
        }
    }

    Component.onCompleted: load()
}
