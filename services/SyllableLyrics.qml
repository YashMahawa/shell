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
    property var sourceCandidates: []
    property var sourceRecords: ({})
    property int sourceRevision: 0
    property string selectedSourceId: ""
    property string pendingNativeSourceId: ""
    property bool userSelectedSource: false
    property bool restoringSources: false
    property bool romanizeLyrics: GlobalConfig.services.romanizeLyrics ?? true
    property int consumerCount: 0
    readonly property bool active: consumerCount > 0
    readonly property string preferredBackend: GlobalConfig.services.lyricsBackend ?? "Auto"

    readonly property alias model: lyricsModel
    readonly property bool hasLyrics: lyricsModel.count > 0
    readonly property string cacheDir: `${Paths.state}/lyrics-plus`
    readonly property var trackSync: {
        if (!root.active) {
            Lyrics.clearTrack();
            return "";
        }
        const p = Players.active;
        if (p)
            Lyrics.setTrack(_queryArtist(), _queryTitle(), p.trackAlbum, p.length);
        else
            Lyrics.clearTrack();
        return p ? `${_queryArtist()} - ${_queryTitle()}` : "";
    }

    onRomanizeLyricsChanged: {
        root.loadedKey = "";
        if (root.active)
            root.load();
    }

    onPreferredBackendChanged: {
        root.loadedKey = "";
        if (root.active)
            root.load();
    }

    function retain(): void {
        consumerCount++;
        if (consumerCount === 1)
            load();
    }

    function release(): void {
        consumerCount = Math.max(0, consumerCount - 1);
        if (consumerCount === 0) {
            loadDebounce.stop();
            cacheDelay.stop();
            paxPreferenceTimeout.stop();
            onlineTimeout.stop();
            youtubeStartDelay.stop();
            youtubeFallbackDelay.stop();
            youtubeTimeout.stop();
            root.requestId++;
            if (youtubeProcess.running)
                youtubeProcess.running = false;
            root.loading = false;
        }
    }

    function _keyForPlayer(): string {
        const p = Players.active;
        if (!p)
            return "";
        return `${_queryArtist()} - ${_queryTitle()}`;
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

    function _sourcePriority(source: string): int {
        const value = String(source || "").toLowerCase();
        if (value.includes("lrcmux"))
            return 0;
        if (value.includes("paxsenix") || value === "local")
            return 1;
        if (value.includes("lrclib") || value.includes("netease"))
            return 2;
        if (value.includes("youtube"))
            return 4;
        return 3;
    }

    function _sourceId(source: string, meta: var): string {
        const provider = String(source || "timed").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
        const rawId = String(meta?.id || meta?.videoId || meta?.sourceTitle || provider || "timed");
        const id = rawId.toLowerCase().replace(/[^a-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "");
        return `${provider}:${id || provider}`;
    }

    function _resetSources(): void {
        nativeSelectionTimeout.stop();
        root.sourceCandidates = [];
        root.sourceRecords = ({});
        root.sourceRevision++;
        root.selectedSourceId = "";
        root.pendingNativeSourceId = "";
        root.userSelectedSource = false;
        root.restoringSources = false;
    }

    function _addSource(lines: var, source: string, message: string, meta: var): string {
        if (!_hasTimedLines(lines))
            return "";

        const details = meta || {};
        const id = details.sourceId || _sourceId(source, details);
        const record = {
            id,
            provider: source || "Timed",
            title: details.title || details.sourceTitle || _queryTitle(),
            artist: details.artist || _queryArtist(),
            detail: message || qsTr("%1 timed lyrics").arg(source || "Timed"),
            language: details.language || "",
            priority: _sourcePriority(source),
            lyrics: lines
        };

        const records = Object.assign({}, root.sourceRecords);
        records[id] = record;
        root.sourceRecords = records;

        const candidates = root.sourceCandidates.filter(candidate => candidate.id !== id);
        candidates.push({
            kind: "external",
            id,
            provider: record.provider,
            title: record.title,
            artist: record.artist,
            detail: record.detail,
            language: record.language,
            priority: record.priority
        });
        candidates.sort((a, b) => a.priority - b.priority || String(a.provider).localeCompare(String(b.provider)));
        root.sourceCandidates = candidates;
        root.sourceRevision++;
        _scheduleCacheSave();
        return id;
    }

    function _selectSource(id: string, byUser: bool): bool {
        const record = root.sourceRecords[id];
        if (!record)
            return false;

        root.selectedSourceId = id;
        root.pendingNativeSourceId = "";
        nativeSelectionTimeout.stop();
        if (byUser)
            root.userSelectedSource = true;
        root.networkSettled = true;
        _loadLines(record.lyrics, record.provider, record.detail);
        _scheduleCacheSave();
        return true;
    }

    function _autoSelectSource(id: string): bool {
        if (!id || root.userSelectedSource)
            return false;
        const candidate = root.sourceRecords[id];
        const selected = root.sourceRecords[root.selectedSourceId];
        if (!selected || candidate.priority < selected.priority)
            return _selectSource(id, false);
        return false;
    }

    function selectSource(id: string): void {
        _selectSource(id, true);
    }

    function nativeSourceId(candidate: var): string {
        if (!candidate)
            return "";
        return `native:${Number(candidate.backend)}:${String(candidate.id || "")}`;
    }

    function selectNativeCandidate(candidate: var): void {
        if (!candidate)
            return;
        nativeSelectionTimeout.previousSourceId = root.selectedSourceId;
        nativeSelectionTimeout.previousUserSelected = root.userSelectedSource;
        root.userSelectedSource = true;
        root.pendingNativeSourceId = nativeSourceId(candidate);
        root.status = qsTr("Loading selected lyric track...");
        nativeSelectionTimeout.restart();
        Lyrics.selectedCandidate = candidate;
        Qt.callLater(() => _captureNativeSource());
    }

    function _captureNativeSource(): string {
        if (!Lyrics.hasLyrics || !_nativeTrackMatches())
            return "";

        const selected = Lyrics.selectedCandidate;
        const backend = LyricsBackend.toString(Lyrics.backend);
        const lines = [];
        for (let i = 0; i < Lyrics.lyrics.length; i++) {
            lines.push({
                time: Math.max(0, Lyrics.timeForIndex(i) - Lyrics.offset) * 1000,
                duration: 0,
                text: Lyrics.lyrics[i],
                syllabus: []
            });
        }
        const selectedId = selected?.id ? nativeSourceId(selected) : `native:${Number(Lyrics.backend)}:${_safeCacheName(root.loadedKey)}`;
        const id = _addSource(lines, backend, qsTr("%1 synced lyrics").arg(backend), {
            sourceId: selectedId,
            id: selected?.id || selectedId,
            title: selected?.title || _queryTitle(),
            artist: selected?.artist || _queryArtist()
        });
        if (!id)
            return "";
        if (root.pendingNativeSourceId && root.pendingNativeSourceId === id)
            _selectSource(id, true);
        else
            _autoSelectSource(id);
        return id;
    }

    function _queryTitle(): string {
        const p = Players.active;
        return String(p?.trackTitle || "")
            .replace(/\s*[\[(](official\s+)?(music\s+)?(video|audio|lyrics?|visuali[sz]er).*?[\])]/ig, "")
            .replace(/\s+-\s+topic$/i, "")
            .trim();
    }

    function _queryArtist(): string {
        const raw = String(Players.active?.trackArtist || "").trim();
        const normalised = raw.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
        return normalised === "teng nong" ? "Sally Kim" : raw;
    }

    function _isPlaceholderTitle(title: string): bool {
        const value = String(title || "").trim().toLowerCase();
        return !value || value === "a site is playing media" || value === "playing media" || value === "unknown title";
    }

    function _paxsenixUrl(): string {
        const artist = _queryArtist();
        const query = `${_queryTitle()} ${artist}`.trim();
        let url = `https://lyrics.paxsenix.org/musixmatch/lyrics?type=word&q=${encodeURIComponent(query)}&t=${encodeURIComponent(_queryTitle())}&a=${encodeURIComponent(artist)}&enchanted=true&alt=true&parse=true&v=2`;
        const duration = _trackDuration();
        if (duration > 0)
            url += `&d=${duration}`;
        return url;
    }

    function _lrcMuxUrl(): string {
        let url = `https://api.lrcmux.dev/compat/kpoe/v2/lyrics/get?title=${encodeURIComponent(_queryTitle())}&artist=${encodeURIComponent(_queryArtist())}`;
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
        const targetArtist = clean(_queryArtist()).split(/[&,xX]/)[0].trim();
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

        const activeArtist = _normaliseTrackText(_queryArtist()).split(/[&,xX]/)[0].trim();
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
        youtubeStartDelay.stop();
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
        if (!root.active)
            return;
        loadDebounce.restart();
    }

    function _doLoad(): void {
        const p = Players.active;
        if (!p || _isPlaceholderTitle(p.trackTitle)) {
            root.requestId++;
            _resetYoutubeFallback();
            _resetSources();
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
        if (changedTrack)
            _resetSources();
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
        if (!root.selectedSourceId)
            root.status = root.cacheLoaded ? qsTr("Refreshing Paxsenix lyrics...") : qsTr("Fetching Paxsenix lyrics...");
        _prepareYoutubeFallback(req);

        paxPreferenceTimeout.requestId = req;
        paxPreferenceTimeout.restart();
        onlineTimeout.requestId = req;
        onlineTimeout.restart();

        Requests.get(_paxsenixUrl(), text => {
            if (req !== root.requestId)
                return;
            try {
                const res = JSON.parse(text);
                const meta = res.cachedMeta || res.metadata || res.track || res.data?.track || {};
                const lines = _extractPaxsenixLines(res);
                if (!_metadataMatches(meta) || !_hasTimedSyllables(lines))
                    throw new Error("Paxsenix did not return word-timed lyrics");
                root.paxFinished = true;
                _settleOnline(req, lines, "Paxsenix", qsTr("Paxsenix word-synced lyrics"));
                _maybeSettleOnline(req);
            } catch (e) {
                root.paxFinished = true;
                _maybeSettleOnline(req);
            }
        }, () => {
            if (req !== root.requestId)
                return;
            root.paxFinished = true;
            _maybeSettleOnline(req);
        }, {}, 7000);

        Requests.get(_lrcMuxUrl(), text => {
            if (req !== root.requestId)
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
            if (_hasTimedLines(root.muxLyrics))
                _settleOnline(req, root.muxLyrics, "LrcMux", qsTr("LrcMux synced lyrics"));
            _maybeSettleOnline(req);
        }, () => {
            if (req !== root.requestId)
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
        if (req !== root.requestId)
            return;
        if (root.paxFinished && root.muxFinished)
            _finishOnlineWithNative(req);
    }

    function _settleOnline(req: int, lines: var, source: string, message: string): void {
        if (req !== root.requestId)
            return;
        const id = _addSource(lines, source, message, {
            title: _queryTitle(),
            artist: _queryArtist()
        });
        if (source === "Paxsenix")
            paxPreferenceTimeout.stop();
        _autoSelectSource(id);
    }

    function _finishOnlineWithNative(req: int): void {
        if (req !== root.requestId)
            return;
        paxPreferenceTimeout.stop();
        onlineTimeout.stop();
        const nativeId = _captureNativeSource();
        if (!nativeId && !Lyrics.loading)
            Lyrics.refresh();
        if (root.youtubeEligible && root.youtubeFinished)
            _useYoutubeResult(req);
        else if (!root.selectedSourceId) {
            root.loading = true;
            if (root.youtubeStarted || root.youtubePending)
                root.status = qsTr("Waiting for YouTube captions...");
        }
    }

    function _prepareYoutubeFallback(req: int): void {
        const p = Players.active;
        const duration = _trackDuration();
        if (req !== root.requestId || !p || !_queryArtist() || duration > 900 || _isPlaceholderTitle(p.trackTitle)) {
            return;
        }

        root.youtubePending = true;
        root.youtubeStarted = true;
        root.youtubeFinished = false;
        root.youtubeEligible = false;
        root.youtubeResult = null;
        root.youtubeFailure = "";
        youtubeStartDelay.requestId = req;
        youtubeStartDelay.restart();
        youtubeFallbackDelay.requestId = req;
        youtubeFallbackDelay.restart();
    }

    function _startYoutubeFallback(req: int): void {
        const p = Players.active;
        if (req !== root.requestId || !p)
            return;
        if (youtubeProcess.running) {
            youtubeProcess.requestId = -1;
            youtubeProcess.running = false;
            youtubeStartDelay.requestId = req;
            youtubeStartDelay.restart();
            return;
        }
        youtubeProcess.requestId = req;
        youtubeProcess.command = [
            "python3",
            `${Quickshell.shellDir}/utils/scripts/youtube_lyrics.py`,
            "--title",
            _queryTitle(),
            "--artist",
            _queryArtist(),
            "--duration",
            String(_trackDuration())
        ];
        youtubeProcess.running = true;
        youtubeTimeout.requestId = req;
        youtubeTimeout.restart();
    }

    function _makeYoutubeEligible(req: int): void {
        if (req !== root.requestId)
            return;

        _captureNativeSource();
        root.youtubeEligible = true;
        if (root.youtubeFinished)
            _useYoutubeResult(req);
        else if (root.youtubeStarted && !root.selectedSourceId) {
            root.loading = true;
            root.status = qsTr("Waiting for parallel YouTube captions...");
        }
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
            const language = result.language ? ` (${result.language})` : "";
            result.sourceId = _addSource(result.lyrics, "YouTube captions", qsTr("YouTube captions%1").arg(language), {
                videoId: result.videoId || "",
                sourceTitle: result.sourceTitle || _queryTitle(),
                title: result.sourceTitle || _queryTitle(),
                artist: _queryArtist(),
                language: result.language || ""
            });
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

        const result = root.youtubeResult;
        if (result) {
            _autoSelectSource(result.sourceId || "");
            root.youtubePending = false;
        } else if (root.selectedSourceId) {
            root.youtubePending = false;
            root.loading = false;
        } else {
            root.youtubePending = false;
            root.loading = Lyrics.loading;
            root.status = qsTr("No lyrics found; YouTube captions unavailable");
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

    function _scheduleCacheSave(): void {
        if (root.restoringSources || !root.loadedKey || !root.cachePath)
            return;
        cacheSaveDelay.restart();
    }

    function _writeSourcesCache(): void {
        if (!root.loadedKey || !root.cachePath)
            return;
        if (saveCache.running) {
            cacheSaveDelay.restart();
            return;
        }

        const sources = [];
        for (const candidate of root.sourceCandidates) {
            const record = root.sourceRecords[candidate.id];
            if (record)
                sources.push(record);
        }
        const payload = JSON.stringify({
            formatVersion: 3,
            key: root.loadedKey,
            romanized: root.romanizeLyrics,
            selectedSourceId: root.selectedSourceId,
            userSelected: root.userSelectedSource,
            sources
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
        running: root.active && root.hasLyrics && !!Players.active
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
            if (requestId !== root.requestId)
                return;
            root.paxFinished = true;
            if (!root.selectedSourceId)
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
            if (requestId !== root.requestId)
                return;
            root.paxFinished = true;
            root.muxFinished = true;
            root._maybeSettleOnline(requestId);
        }
    }

    Timer {
        id: youtubeStartDelay

        property int requestId: -1

        interval: 180
        repeat: false
        onTriggered: root._startYoutubeFallback(requestId)
    }

    Timer {
        id: youtubeFallbackDelay

        property int requestId: -1

        interval: 7000
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
                if (cached.key !== root.loadedKey)
                    return;

                root.restoringSources = true;
                let selectedId = "";
                if (cached.formatVersion === 3 && Array.isArray(cached.sources)) {
                    for (const source of cached.sources || []) {
                        const id = root._addSource(source.lyrics || [], source.provider || "Cached", source.detail || qsTr("Cached timed lyrics"), {
                            sourceId: source.id || "",
                            title: source.title || root._queryTitle(),
                            artist: source.artist || root._queryArtist(),
                            language: source.language || ""
                        });
                        if (!selectedId)
                            selectedId = id;
                    }
                    if (cached.selectedSourceId && root.sourceRecords[cached.selectedSourceId])
                        selectedId = cached.selectedSourceId;
                    root.userSelectedSource = !!cached.userSelected;
                } else if (root._hasTimedLines(cached.lyrics)) {
                    selectedId = root._addSource(cached.lyrics, cached.provider || "Cached", qsTr("Cached %1 lyrics; refreshing...").arg(cached.provider || "timed"), {
                        title: root._queryTitle(),
                        artist: root._queryArtist()
                    });
                }
                root.restoringSources = false;
                if (selectedId) {
                    root.cacheLoaded = true;
                    root._selectSource(selectedId, false);
                }
            } catch (e) {
                root.restoringSources = false;
                root.cacheLoaded = false;
            }
        }
    }

    Timer {
        id: nativeSelectionTimeout

        property string previousSourceId: ""
        property bool previousUserSelected: false

        interval: 10000
        repeat: false
        onTriggered: {
            if (!root.pendingNativeSourceId)
                return;
            root.pendingNativeSourceId = "";
            root.userSelectedSource = previousUserSelected;
            const previous = root.sourceRecords[previousSourceId];
            if (previous) {
                root.selectedSourceId = previousSourceId;
                root.provider = previous.provider;
                root.status = previous.detail;
                root.loading = false;
            } else {
                root.loading = false;
                root.status = qsTr("Selected lyric track unavailable");
            }
        }
    }

    Timer {
        id: cacheSaveDelay

        interval: 180
        repeat: false
        onTriggered: root._writeSourcesCache()
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
            if (root.active)
                root.load();
        }
    }

    Connections {
        target: Players.active
        ignoreUnknownSignals: true
        function onPostTrackChanged(): void {
            if (root.active)
                root.load();
        }
        function onTrackTitleChanged(): void {
            if (root.active)
                root.load();
        }
        function onTrackArtistChanged(): void {
            if (root.active)
                root.load();
        }
    }

    Connections {
        target: Lyrics
        function onLyricsChanged(): void {
            root._captureNativeSource();
        }
        function onLoadingChanged(): void {
            if (!root.selectedSourceId)
                root.loading = Lyrics.loading || root.youtubePending || root.youtubeStarted;
        }
    }

}
