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
    property string provider: ""
    property string status: ""
    property bool cacheLoaded: false
    property bool ownsTiming: false
    property bool networkSettled: false
    property bool paxFinished: false
    property bool muxFinished: false
    property var muxLyrics: []
    property string muxSource: ""
    property bool youtubePending: false
    property bool youtubeStarted: false
    property bool youtubeFinished: false
    property bool youtubeEligible: false
    property var youtubeResult: null
    property string youtubeFailure: ""
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

    function _queryTitle(): string {
        const p = Players.active;
        return String(p?.trackTitle || "")
            .replace(/\s*[\[(](official\s+)?(music\s+)?(video|audio|lyrics?|visuali[sz]er).*?[\])]/ig, "")
            .replace(/\s+-\s+topic$/i, "")
            .trim();
    }

    function _isPlaceholderTitle(title: string): bool {
        const value = String(title || "").trim().toLowerCase();
        return !value || value === "a site is playing media" || value === "playing media" || value === "unknown title";
    }

    function _paxsenixUrl(): string {
        const p = Players.active;
        const query = `${_queryTitle()} ${p?.trackArtist || ""}`.trim();
        let url = `https://lyrics.paxsenix.org/musixmatch/lyrics?type=word&q=${encodeURIComponent(query)}&t=${encodeURIComponent(_queryTitle())}&a=${encodeURIComponent(p?.trackArtist || "")}&enchanted=true&alt=true&parse=true&v=2`;
        const duration = _trackDuration();
        if (duration > 0)
            url += `&d=${duration}`;
        return url;
    }

    function _lrcMuxUrl(): string {
        const p = Players.active;
        let url = `https://api.lrcmux.dev/compat/kpoe/v2/lyrics/get?title=${encodeURIComponent(_queryTitle())}&artist=${encodeURIComponent(p?.trackArtist || "")}`;
        const duration = _trackDuration();
        if (duration > 0)
            url += `&duration=${duration}`;
        return url;
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

    function _normaliseTrackText(value: string): string {
        return String(value || "").toLowerCase().replace(/\s*\(.*?\)/g, "").replace(/\s*\[.*?\]/g, "").trim();
    }

    function _nativeTrackMatches(): bool {
        const p = Players.active;
        if (!p || !p.trackTitle)
            return false;

        const activeTitle = _normaliseTrackText(p.trackTitle);
        const nativeTitle = _normaliseTrackText(Lyrics.trackTitle);
        if (!activeTitle || !nativeTitle || activeTitle !== nativeTitle)
            return false;

        const activeArtist = _normaliseTrackText(p.trackArtist).split(/[&,xX]/)[0].trim();
        const nativeArtist = _normaliseTrackText(Lyrics.trackArtist).split(/[&,xX]/)[0].trim();
        return !activeArtist || !nativeArtist || activeArtist === nativeArtist || activeArtist.includes(nativeArtist) || nativeArtist.includes(activeArtist);
    }

    function _clearDisplayedLyrics(status: string): void {
        lyricsModel.clear();
        root.hasSyllables = false;
        root.ownsTiming = false;
        root.currentIndex = -1;
        root.provider = "";
        root.status = status || "";
        root.revision++;
    }

    function _resetYoutubeFallback(): void {
        youtubeFallbackDelay.stop();
        youtubeTimeout.stop();
        root.youtubePending = false;
        root.youtubeStarted = false;
        root.youtubeFinished = false;
        root.youtubeEligible = false;
        root.youtubeResult = null;
        root.youtubeFailure = "";
        youtubeProcess.requestId = -1;
        if (youtubeProcess.running)
            youtubeProcess.running = false;
    }

    function _setNativeFallback(): void {
        if (root.ownsTiming)
            return;

        lyricsModel.clear();
        const nativeReady = Lyrics.hasLyrics && _nativeTrackMatches();
        const lines = nativeReady ? Lyrics.lyrics : [];
        for (let i = 0; i < lines.length; i++) {
            lyricsModel.append({
                lyricLine: _cleanText(lines[i]) || ". . .",
                time: Lyrics.timeForIndex(i),
                syllabus: "[]"
            });
        }
        root.loading = nativeReady ? Lyrics.loading : false;
        root.ownsTiming = nativeReady;
        root.currentIndex = nativeReady ? Lyrics.indexForTime(Players.active?.position ?? 0) : -1;
        root.provider = nativeReady ? LyricsBackend.toString(Lyrics.backend) : "";
        root.status = nativeReady ? qsTr("Fallback: %1").arg(root.provider) : qsTr("No lyrics found");
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

    function _hasTimedLines(lines: var): bool {
        if (!lines || lines.length === 0)
            return false;
        return lines.some(line => Number(line.time ?? line.start ?? line.startTimeMs ?? 0) > 0 && String(line.text ?? line.words ?? line.x ?? "").trim().length > 0);
    }

    function load(): void {
        loadDebounce.restart();
    }

    function _doLoad(): void {
        const p = Players.active;
        if (!p || _isPlaceholderTitle(p.trackTitle)) {
            root.requestId++;
            _resetYoutubeFallback();
            root.loadedKey = "";
            root.cachePath = "";
            root.cacheLoaded = false;
            root.networkSettled = true;
            root.paxFinished = true;
            root.muxFinished = true;
            root.muxLyrics = [];
            root.muxSource = "";
            cacheDelay.stop();
            paxPreferenceTimeout.stop();
            onlineTimeout.stop();
            root.loading = false;
            _clearDisplayedLyrics(p ? qsTr("Waiting for track metadata...") : qsTr("No active track"));
            return;
        }

        const key = _keyForPlayer();
        if (key && key === root.loadedKey && lyricsModel.count > 0)
            return;

        const changedTrack = key !== root.loadedKey;
        root.loadedKey = key;
        root.hasSyllables = false;
        root.loading = true;
        root.currentIndex = -1;
        root.requestId++;
        _resetYoutubeFallback();
        const req = root.requestId;
        root.networkSettled = false;
        root.paxFinished = false;
        root.muxFinished = false;
        root.muxLyrics = [];
        root.muxSource = "";
        paxPreferenceTimeout.stop();
        onlineTimeout.stop();

        if (changedTrack)
            _clearDisplayedLyrics(qsTr("Loading lyrics..."));

        if (!_usePaxsenix()) {
            root.loading = Lyrics.loading;
            root.status = qsTr("Loading fallback lyrics...");
            _setNativeFallback();
            return;
        }

        root.provider = "Paxsenix";
        root.status = qsTr("Fetching Paxsenix lyrics...");
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

        root.networkSettled = false;
        root.paxFinished = false;
        root.muxFinished = false;
        root.muxLyrics = [];
        root.muxSource = "";
        root.status = root.cacheLoaded ? qsTr("Refreshing Paxsenix lyrics...") : qsTr("Fetching Paxsenix lyrics...");
        _prepareYoutubeFallback(req);

        paxPreferenceTimeout.requestId = req;
        paxPreferenceTimeout.restart();
        onlineTimeout.requestId = req;
        onlineTimeout.restart();

        Requests.get(_paxsenixUrl(), text => {
            if (req !== root.requestId || root.networkSettled)
                return;
            try {
                const res = JSON.parse(text);
                const meta = res.cachedMeta || res.metadata || res.track || res.data?.track || {};
                const lines = _extractPaxsenixLines(res);
                if (!_metadataMatches(meta) || !_hasTimedSyllables(lines))
                    throw new Error("Paxsenix did not return word-timed lyrics");
                _settleOnline(req, lines, "Paxsenix", qsTr("Paxsenix word-synced lyrics"));
            } catch (e) {
                root.paxFinished = true;
                _maybeSettleOnline(req);
            }
        }, () => {
            if (req !== root.requestId || root.networkSettled)
                return;
            root.paxFinished = true;
            _maybeSettleOnline(req);
        }, {}, 7000);

        Requests.get(_lrcMuxUrl(), text => {
            if (req !== root.requestId || root.networkSettled)
                return;
            try {
                const res = JSON.parse(text);
                const lines = res.lyrics || [];
                if (!_hasTimedLines(lines))
                    throw new Error("LrcMux did not return timed lyrics");
                root.muxLyrics = lines;
                root.muxSource = res.metadata?.source || "LrcMux";
            } catch (e) {
                root.muxLyrics = [];
            }
            root.muxFinished = true;
            _maybeSettleOnline(req);
        }, () => {
            if (req !== root.requestId || root.networkSettled)
                return;
            root.muxFinished = true;
            _maybeSettleOnline(req);
        }, {}, 12000);
    }

    function _extractPaxsenixLines(res: var): var {
        let rich = res?.richsync ?? res?.data?.richsync ?? res?.lyrics?.richsync ?? res?.data?.lyrics?.richsync;
        if (typeof rich === "string") {
            try {
                rich = JSON.parse(rich);
            } catch (e) {
                rich = undefined;
            }
        }

        let lines = Array.isArray(rich) ? rich : res?.lyrics;
        if (!Array.isArray(lines))
            lines = res?.data?.lyrics?.lines ?? res?.data?.lines ?? res?.lyrics?.lines ?? res?.lines ?? [];
        if (!Array.isArray(lines))
            return [];
        if (_hasTimedSyllables(lines))
            return lines;

        const normalised = [];
        for (const line of lines) {
            const richLine = line?.ts !== undefined;
            const start = richLine ? Number(line.ts || 0) * 1000 : Number(line.time ?? line.startTimeMs ?? line.start ?? 0);
            const end = richLine ? Number(line.te || line.ts || 0) * 1000 : Number(line.endTimeMs ?? line.end ?? 0);
            const rawWords = Array.isArray(line.syllabus) ? line.syllabus : Array.isArray(line.syllables) ? line.syllables : Array.isArray(line.words) ? line.words : Array.isArray(line.l) ? line.l : [];
            const syllables = [];
            for (let i = 0; i < rawWords.length; i++) {
                const word = rawWords[i];
                let wordStart = Number(word.time ?? word.startTimeMs ?? word.start ?? 0);
                let wordEnd = Number(word.endTimeMs ?? word.end ?? 0);
                if (richLine && word.o !== undefined) {
                    wordStart = start + Number(word.o || 0) * 1000;
                    const next = rawWords[i + 1];
                    wordEnd = next?.o !== undefined ? start + Number(next.o) * 1000 : end;
                }
                const duration = Number(word.duration ?? Math.max(0, wordEnd - wordStart));
                syllables.push({
                    time: wordStart,
                    duration,
                    text: String(word.text ?? word.words ?? word.c ?? "")
                });
            }
            normalised.push({
                time: start,
                duration: Math.max(0, end - start),
                text: String(line.text ?? line.x ?? (typeof line.words === "string" ? line.words : "")),
                syllabus: syllables
            });
        }
        return normalised;
    }

    function _maybeSettleOnline(req: int): void {
        if (req !== root.requestId || root.networkSettled)
            return;
        if (root.paxFinished && _hasTimedLines(root.muxLyrics)) {
            _settleOnline(req, root.muxLyrics, "LrcMux", qsTr("Fallback: %1").arg(root.muxSource));
            return;
        }
        if (root.paxFinished && root.muxFinished)
            _finishOnlineWithNative(req);
    }

    function _settleOnline(req: int, lines: var, source: string, message: string): void {
        if (req !== root.requestId || root.networkSettled)
            return;
        root.networkSettled = true;
        _resetYoutubeFallback();
        paxPreferenceTimeout.stop();
        onlineTimeout.stop();
        _loadLines(lines, source, message);
        _saveCache(lines, source);
    }

    function _finishOnlineWithNative(req: int): void {
        if (req !== root.requestId || root.networkSettled)
            return;
        root.networkSettled = true;
        paxPreferenceTimeout.stop();
        onlineTimeout.stop();
        if (root.cacheLoaded && root.hasLyrics) {
            _resetYoutubeFallback();
            root.loading = false;
            root.status = qsTr("Cached %1 lyrics; providers unavailable").arg(root.provider || "timed");
            return;
        }
        root.status = qsTr("Paxsenix and LrcMux unavailable; checking native lyrics...");
        Lyrics.refresh();
        _setNativeFallback();
        if (root.ownsTiming)
            _resetYoutubeFallback();
        else if (root.youtubeEligible && root.youtubeFinished)
            _useYoutubeResult(req);
        else {
            root.loading = true;
            if (root.youtubeStarted || root.youtubePending)
                root.status = qsTr("Waiting for YouTube captions...");
        }
    }

    function _prepareYoutubeFallback(req: int): void {
        const p = Players.active;
        const duration = _trackDuration();
        if (req !== root.requestId || root.ownsTiming || !p || !p.trackArtist || duration > 900 || _isPlaceholderTitle(p.trackTitle)) {
            return;
        }

        root.youtubePending = true;
        root.youtubeStarted = true;
        root.youtubeFinished = false;
        root.youtubeEligible = false;
        root.youtubeResult = null;
        root.youtubeFailure = "";
        youtubeProcess.requestId = req;
        youtubeProcess.command = [
            "python3",
            `${Quickshell.shellDir}/utils/scripts/youtube_lyrics.py`,
            "--title",
            _queryTitle(),
            "--artist",
            p.trackArtist || "",
            "--duration",
            String(_trackDuration())
        ];
        youtubeProcess.running = true;
        youtubeFallbackDelay.requestId = req;
        youtubeFallbackDelay.restart();
        youtubeTimeout.requestId = req;
        youtubeTimeout.restart();
    }

    function _makeYoutubeEligible(req: int): void {
        if (req !== root.requestId)
            return;

        _setNativeFallback();
        if (root.ownsTiming) {
            root.networkSettled = true;
            paxPreferenceTimeout.stop();
            onlineTimeout.stop();
            _resetYoutubeFallback();
            return;
        }

        root.youtubeEligible = true;
        root.loading = true;
        if (root.youtubeFinished)
            _useYoutubeResult(req);
        else if (root.youtubeStarted)
            root.status = qsTr("Other providers took over 10 seconds; waiting for YouTube captions...");
    }

    function _finishYoutubeFallback(req: int, output: string, errorOutput: string): void {
        if (req !== root.requestId)
            return;

        youtubeTimeout.stop();
        root.youtubeStarted = false;
        root.youtubeFinished = true;
        try {
            const result = JSON.parse(output || "{}");
            if (!result.success || !_hasTimedLines(result.lyrics || []))
                throw new Error(result.error || errorOutput || "No usable YouTube captions");
            root.youtubeResult = result;
            root.youtubeFailure = "";
        } catch (e) {
            root.youtubeResult = null;
            root.youtubeFailure = String(e);
        }

        if (root.youtubeEligible)
            _useYoutubeResult(req);
    }

    function _useYoutubeResult(req: int): void {
        if (req !== root.requestId)
            return;

        _setNativeFallback();
        if (root.ownsTiming) {
            root.networkSettled = true;
            paxPreferenceTimeout.stop();
            onlineTimeout.stop();
            _resetYoutubeFallback();
            return;
        }

        const result = root.youtubeResult;
        if (result) {
            root.networkSettled = true;
            paxPreferenceTimeout.stop();
            onlineTimeout.stop();
            _resetYoutubeFallback();
            const language = result.language ? ` (${result.language})` : "";
            _loadLines(result.lyrics, "YouTube captions", qsTr("Fallback: YouTube captions%1").arg(language));
            _saveCache(result.lyrics, "YouTube captions");
        } else if (root.networkSettled) {
            root.youtubePending = false;
            root.loading = Lyrics.loading;
            _setNativeFallback();
            if (!root.ownsTiming)
                root.status = qsTr("No lyrics found; YouTube captions unavailable");
        } else {
            root.youtubePending = false;
            root.status = qsTr("YouTube captions unavailable; waiting for other providers...");
        }
    }

    function _loadLines(lines: var, source: string, message: string): void {
        if (!_hasTimedLines(lines)) {
            root.hasSyllables = false;
            root.ownsTiming = false;
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
        root.ownsTiming = lyricsModel.count > 0;
        root.loading = false;
        root.provider = source || "Timed";
        root.status = message || qsTr("%1 timed lyrics").arg(root.provider);
        root.revision++;
        updatePosition();
    }

    function _saveCache(lines: var, source: string): void {
        const payload = JSON.stringify({
            formatVersion: 2,
            key: root.loadedKey,
            provider: source || root.provider,
            romanized: root.romanizeLyrics,
            lyrics: lines
        });
        saveCache.command = ["sh", "-c", `mkdir -p ${_shellQuote(root.cacheDir)} && printf %s ${_shellQuote(payload)} > ${_shellQuote(root.cachePath)}`];
        saveCache.running = true;
    }

    function indexForTime(time: real): int {
        if (!root.ownsTiming)
            return Lyrics.indexForTime(time);

        const target = time - Lyrics.offset + 0.1;
        for (let i = lyricsModel.count - 1; i >= 0; i--) {
            if (target >= lyricsModel.get(i).time)
                return i;
        }
        return -1;
    }

    function timeForIndex(index: int): real {
        if (index < 0)
            return 0;
        if (!root.ownsTiming)
            return Lyrics.timeForIndex(index);
        return (lyricsModel.get(index)?.time ?? 0) + Lyrics.offset;
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
            if (requestId === root.requestId)
                root._fetchOnline(requestId);
        }
    }

    Timer {
        id: paxPreferenceTimeout

        property int requestId: -1

        interval: 7000
        repeat: false
        onTriggered: {
            if (requestId !== root.requestId || root.networkSettled)
                return;
            root.paxFinished = true;
            root.status = qsTr("Paxsenix timed out; using word-sync fallback");
            root._maybeSettleOnline(requestId);
        }
    }

    Timer {
        id: onlineTimeout

        property int requestId: -1

        interval: 15000
        repeat: false
        onTriggered: {
            if (requestId !== root.requestId || root.networkSettled)
                return;
            root.paxFinished = true;
            root.muxFinished = true;
            root._maybeSettleOnline(requestId);
        }
    }

    Timer {
        id: youtubeFallbackDelay

        property int requestId: -1

        interval: 10000
        repeat: false
        onTriggered: root._makeYoutubeEligible(requestId)
    }

    Timer {
        id: youtubeTimeout

        property int requestId: -1

        interval: 38000
        repeat: false
        onTriggered: {
            if (requestId !== root.requestId)
                return;
            youtubeProcess.requestId = -1;
            if (youtubeProcess.running)
                youtubeProcess.running = false;
            root.youtubeStarted = false;
            root.youtubeFinished = true;
            root.youtubeResult = null;
            root.youtubeFailure = "YouTube captions timed out";
            if (root.youtubeEligible)
                root._useYoutubeResult(requestId);
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
                const currentFormat = cached.provider !== "YouTube captions" || cached.formatVersion === 2;
                if (currentFormat && cached.key === root.loadedKey && _hasTimedLines(cached.lyrics)) {
                    root.cacheLoaded = true;
                    root._loadLines(cached.lyrics, cached.provider || "Cached", qsTr("Cached %1 lyrics; refreshing...").arg(cached.provider || "timed"));
                }
            } catch (e) {
                root.cacheLoaded = false;
            }
        }
    }

    Process {
        id: saveCache
    }

    Process {
        id: youtubeProcess

        property int requestId: -1

        stdout: StdioCollector {
            id: youtubeOutput
        }
        stderr: StdioCollector {
            id: youtubeError
        }
        onExited: _code => root._finishYoutubeFallback(requestId, youtubeOutput.text, youtubeError.text) // qmllint disable signal-handler-parameters
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
            if (root.networkSettled || !root._usePaxsenix()) {
                root._setNativeFallback();
                if (root.ownsTiming)
                    root._resetYoutubeFallback();
            }
        }
        function onLoadingChanged(): void {
            if (!root.ownsTiming && (root.networkSettled || !root._usePaxsenix()))
                root.loading = Lyrics.loading || root.youtubePending || root.youtubeStarted;
        }
    }

    Component.onCompleted: load()
}
