pragma Singleton

import "../utils/scripts/lrcparser.js" as Lrc
import "../utils/scripts/lyricproviders.js" as Providers
import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.utils

// Timed lyrics for the active player.
//
// Sources follow BitChord's LyricsRepository: every provider is started in
// parallel and the highest-ranked word-synced result wins, falling back to the
// highest-ranked line-synced one. To keep the first paint fast, a result is
// shown as soon as nothing ranked above it is still pending, or after a short
// grace period; a better result may still replace it while the song is young.
//
// Lyrics are also prefetched for the playing track, so opening the immersive
// view or the dashboard shows them immediately.
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
    property bool youtubeStarted: false
    property bool youtubeFinished: false
    property bool youtubeEligible: false
    property string youtubeFailure: ""
    property var sourceCandidates: []
    property var sourceRecords: ({})
    property int sourceRevision: 0
    property string selectedSourceId: ""
    property string pendingNativeSourceId: ""
    property bool userSelectedSource: false
    property bool restoringSources: false
    property var pending: ({})
    property real fetchStartedAt: 0
    property real shownAt: 0
    property string appleToken: ""
    property bool romanizeLyrics: GlobalConfig.services.romanizeLyrics ?? true
    property int consumerCount: 0
    readonly property bool prefetch: !!Players.active
    readonly property bool active: consumerCount > 0 || prefetch
    readonly property bool visibleConsumers: consumerCount > 0
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

    onActiveChanged: {
        if (active)
            load();
        else
            _cancel();
    }

    onVisibleConsumersChanged: {
        if (visibleConsumers)
            updatePosition();
    }

    function retain(): void {
        consumerCount++;
        if (consumerCount === 1)
            load();
    }

    function release(): void {
        consumerCount = Math.max(0, consumerCount - 1);
    }

    function _cancel(): void {
        loadDebounce.stop();
        cacheDelay.stop();
        graceTimer.stop();
        root.requestId++;
        root.pending = ({});
        if (youtubeProcess.running)
            youtubeProcess.running = false;
        root.loading = false;
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

    function _track(): var {
        return {
            title: Providers.searchTitle(_queryTitle()),
            artist: Providers.searchArtist(_queryArtist()),
            album: Players.active?.trackAlbum || "",
            duration: _trackDuration() * 1000
        };
    }

    function _youtubeId(): string {
        const url = String(Players.active?.metadata?.["xesam:url"] || "");
        return url.match(/[?&]v=([\w-]{11})/)?.[1] || url.match(/youtu\.be\/([\w-]{11})/)?.[1] || "";
    }

    function _cleanText(text: string): string {
        const clean = (text || "").replace(/ /g, " ");
        return root.romanizeLyrics ? Lrc.transliterate(clean) : clean;
    }

    function _useOnline(): bool {
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

    // Lower is better: word-synced results always beat line-synced ones, then
    // BitChord's provider order decides.
    function _effectiveRank(record: var): int {
        return (record.wordSynced ? 0 : 100) + Number(record.priority ?? 99);
    }

    function _providerRank(providerId: string): int {
        if (providerId === "native")
            return Providers.rankOf("lrclib");
        return Providers.rankOf(providerId);
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
        root.shownAt = 0;
    }

    function _addSource(lines: var, providerId: string, label: string, message: string, meta: var): string {
        if (!Providers.hasLineTiming(lines))
            return "";

        const details = meta || {};
        const id = details.sourceId || `${providerId}:${_safeCacheName(details.id || providerId)}`;
        const record = {
            id,
            providerId,
            provider: label,
            title: details.title || _queryTitle(),
            artist: details.artist || _queryArtist(),
            detail: message,
            language: details.language || "",
            priority: _providerRank(providerId),
            wordSynced: Providers.hasWordTiming(lines),
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
            priority: _effectiveRank(record)
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
        // Japanese, Chinese and Korean are shown only once romanised.
        if (root.romanizeLyrics && _needsRomanizer(record.lyrics)) {
            if (!record.romanized) {
                _romanize(record);
                return true;
            }
            if (!root.shownAt)
                root.shownAt = Date.now();
            _loadLines(record.romanized, record.provider, record.detail);
            _scheduleCacheSave();
            return true;
        }
        if (!root.shownAt)
            root.shownAt = Date.now();
        _loadLines(record.lyrics, record.provider, record.detail);
        _scheduleCacheSave();
        return true;
    }

    function _needsRomanizer(lines: var): bool {
        const cjk = /[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7a3]/;
        for (let i = 0; i < Math.min(lines.length, 80); i++) {
            if (cjk.test(lines[i].text || "") || cjk.test(lines[i].bg?.text || ""))
                return true;
        }
        return false;
    }

    function _romanize(record: var): void {
        if (romanizer.running)
            romanizer.running = false;
        root.loading = true;
        root.status = qsTr("Romanising lyrics...");
        romanizer.recordId = record.id;
        romanizer.requestId = root.requestId;
        romanizer.payload = JSON.stringify({ lines: record.lyrics });
        romanizer.running = true;
    }

    // BitChord's race: walk providers in rank order and take the best result
    // once nothing ranked above it can still arrive.
    function _reconsider(req: int, graceExpired: bool): void {
        if (req !== root.requestId || root.userSelectedSource)
            return;

        let best = null;
        for (const id in root.sourceRecords) {
            const record = root.sourceRecords[id];
            if (!best || _effectiveRank(record) < _effectiveRank(best))
                best = record;
        }

        const pendingIds = Object.keys(root.pending);
        root.networkSettled = pendingIds.length === 0;
        if (!best) {
            if (root.networkSettled)
                _onNothingFound(req);
            return;
        }

        const current = root.sourceRecords[root.selectedSourceId];
        if (current && current.id === best.id) {
            root.loading = false;
            return;
        }

        // Anything still running that could outrank the best result blocks it.
        const bestRank = _effectiveRank(best);
        const blocked = pendingIds.some(id => _providerRank(id) < bestRank);

        if (!current) {
            if (!blocked || graceExpired || root.networkSettled)
                _selectSource(best.id, false);
            return;
        }

        // Replacing lyrics the listener is already reading is jarring; only do
        // it early in the song, or to upgrade line timing to word timing.
        if (_effectiveRank(best) < _effectiveRank(current)
                && ((best.wordSynced && !current.wordSynced) || Date.now() - root.shownAt < 4500))
            _selectSource(best.id, false);
    }

    function _onNothingFound(req: int): void {
        if (req !== root.requestId)
            return;
        if (!root.youtubeStarted && !root.youtubeFinished && _startYoutube(req))
            return;
        if (!root.selectedSourceId && !root.youtubeStarted) {
            root.loading = Lyrics.loading;
            if (!Lyrics.loading)
                _setNativeFallback();
        }
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
                syllabus: [],
                agent: "start",
                bg: null
            });
        }
        const selectedId = selected?.id ? nativeSourceId(selected) : `native:${Number(Lyrics.backend)}:${_safeCacheName(root.loadedKey)}`;
        const id = _addSource(Providers.parseLegacy(lines), "native", backend, qsTr("%1 synced lyrics").arg(backend), {
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
            _reconsider(root.requestId, false);
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

    // Rejects a provider answer that is clearly a different recording.
    function _matchesTrack(title: string, artist: string, durationSeconds: real): bool {
        const p = Players.active;
        if (!p)
            return false;
        const wantTitle = _normaliseTrackText(_queryTitle());
        const gotTitle = _normaliseTrackText(title);
        if (gotTitle && wantTitle && gotTitle !== wantTitle && !gotTitle.includes(wantTitle) && !wantTitle.includes(gotTitle))
            return false;
        const wantArtist = _normaliseTrackText(_queryArtist()).split(/[&,]/)[0].trim();
        const gotArtist = _normaliseTrackText(artist);
        if (gotArtist && wantArtist && !gotArtist.includes(wantArtist) && !wantArtist.includes(gotArtist.split(/[&,]/)[0].trim()))
            return false;
        const duration = _trackDuration();
        if (duration > 0 && durationSeconds > 0 && Math.abs(durationSeconds - duration) > 15)
            return false;
        return true;
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

    function _appendLine(text: string, time: real, duration: real, syllables: var, agent: string, bg: var): void {
        lyricsModel.append({
            lyricLine: text,
            time,
            duration,
            syllabus: JSON.stringify(syllables),
            agent: agent || "start",
            bgText: bg?.text || "",
            bgSyllabus: JSON.stringify(bg?.syllabus || [])
        });
    }

    function _setNativeFallback(): void {
        if (root.ownsTiming)
            return;

        lyricsModel.clear();
        const nativeReady = Lyrics.hasLyrics && _nativeTrackMatches();
        const lines = nativeReady ? Lyrics.lyrics : [];
        for (let i = 0; i < lines.length; i++) {
            const start = Lyrics.timeForIndex(i);
            const next = i + 1 < lines.length ? Lyrics.timeForIndex(i + 1) : start + 4;
            _appendLine(_cleanText(lines[i]) || ". . .", start, Math.max(0, next - start), [], "start", null);
        }
        root.loading = nativeReady ? Lyrics.loading : false;
        root.ownsTiming = nativeReady;
        root.currentIndex = nativeReady ? Lyrics.indexForTime(Players.active?.position ?? 0) : -1;
        root.provider = nativeReady ? LyricsBackend.toString(Lyrics.backend) : "";
        root.status = nativeReady ? qsTr("Fallback: %1").arg(root.provider) : qsTr("No lyrics found");
        root.revision++;
    }

    function load(): void {
        if (!root.active)
            return;
        loadDebounce.restart();
    }

    function _doLoad(): void {
        const p = Players.active;
        if (!p || _isPlaceholderTitle(p.trackTitle)) {
            _cancel();
            _resetSources();
            root.loadedKey = "";
            root.cachePath = "";
            root.cacheLoaded = false;
            root.networkSettled = true;
            _clearDisplayedLyrics(p ? qsTr("Waiting for track metadata...") : qsTr("No active track"));
            return;
        }

        const key = _keyForPlayer();
        if (key && key === root.loadedKey && (lyricsModel.count > 0 || Object.keys(root.pending).length > 0))
            return;

        const changedTrack = key !== root.loadedKey;
        root.loadedKey = key;
        root.loading = true;
        root.currentIndex = -1;
        _cancel();
        root.loading = true;
        root.youtubeStarted = false;
        root.youtubeFinished = false;
        root.youtubeEligible = false;
        root.youtubeFailure = "";
        if (changedTrack) {
            _resetSources();
            _clearDisplayedLyrics(qsTr("Loading lyrics..."));
        }
        const req = root.requestId;
        root.networkSettled = false;

        if (!_useOnline()) {
            root.loading = Lyrics.loading;
            root.status = qsTr("Loading fallback lyrics...");
            _setNativeFallback();
            return;
        }

        root.status = qsTr("Finding lyrics...");
        root.cacheLoaded = false;
        _setCachePath(key);
        cacheFile.reload();
        cacheDelay.requestId = req;
        cacheDelay.restart();
    }

    // ---- providers ----------------------------------------------------------

    function _begin(req: int, id: string): void {
        if (req !== root.requestId)
            return;
        const next = Object.assign({}, root.pending);
        next[id] = true;
        root.pending = next;
    }

    function _settle(req: int, id: string, lines: var, meta: var): void {
        if (req !== root.requestId)
            return;
        const next = Object.assign({}, root.pending);
        delete next[id];
        root.pending = next;
        if (lines && Providers.hasLineTiming(lines)) {
            const info = Providers.providerFor(id);
            const word = Providers.hasWordTiming(lines);
            _addSource(lines, id, info?.name ?? id,
                word ? qsTr("Word-synced lyrics") : qsTr("Line-synced lyrics"),
                meta || {});
        }
        _reconsider(req, false);
    }

    function _get(req: int, id: string, url: string, timeout: int, onText: var): void {
        Requests.get(url, text => {
            if (req !== root.requestId)
                return;
            let lines = null;
            try {
                lines = onText(text);
            } catch (e) {
                lines = null;
            }
            // `undefined` means the handler chained another request.
            if (lines !== undefined)
                _settle(req, id, lines, null);
        }, () => _settle(req, id, null, null), { "User-Agent": "BitChord (https://github.com/bitchord)", "Accept": "application/json" }, timeout);
    }

    function _fetchOnline(req: int): void {
        const p = Players.active;
        if (!p || !p.trackTitle || req !== root.requestId)
            return;

        const t = _track();
        root.fetchStartedAt = Date.now();
        if (!root.selectedSourceId)
            root.status = qsTr("Finding lyrics...");
        graceTimer.requestId = req;
        graceTimer.restart();

        // Register every provider first so none can settle the race early.
        const videoId = _youtubeId();
        const ids = ["bini", "betterlyrics", "portato", "lyricsplus", "lrcmux", "unison", "kugou", "lrclib", "musixmatch"];
        if (root.appleToken)
            ids.push("paxsenix-apple");
        if (videoId)
            ids.push("simpmusic");
        for (const id of ids)
            _begin(req, id);

        _get(req, "bini", Providers.biniSearchUrl(t), 5000, text => {
            const res = JSON.parse(text);
            const hit = res.results?.[0];
            if (!hit?.lyricsUrl)
                return null;
            _get(req, "bini", hit.lyricsUrl, 6000, ttml => Providers.parseTtml(ttml));
            return undefined;
        });

        _get(req, "betterlyrics", Providers.betterLyricsUrl(t), 6000, text => Providers.parseTtml(JSON.parse(text).ttml || ""));
        _get(req, "portato", Providers.portatoUrl(t), 5000, text => Providers.parseTtml(JSON.parse(text).ttml || ""));
        _fetchLyricsPlus(req, t, 0);
        _get(req, "lrcmux", Providers.lrcMuxUrl(t), 8000, text => Providers.parseKpoe(JSON.parse(text)));
        _get(req, "unison", Providers.unisonUrl(t), 6000, text => {
            const res = JSON.parse(text);
            const data = res.success ? res.data : null;
            if (!data?.lyrics)
                return null;
            if (String(data.format).toLowerCase() === "ttml")
                return Providers.parseTtml(data.lyrics);
            return String(data.syncType).toLowerCase() === "plain" ? null : Providers.parseLrc(data.lyrics);
        });
        _get(req, "kugou", Providers.kugouSearchUrl(t), 8000, text => {
            const candidate = Providers.bestKugouCandidate(JSON.parse(text), t);
            if (!candidate)
                return null;
            _get(req, "kugou", Providers.kugouDownloadUrl(candidate.id, candidate.accesskey), 6000,
                body => Providers.parseLrc(Providers.decodeBase64Utf8(JSON.parse(body).content)));
            return undefined;
        });
        _get(req, "lrclib", Providers.lrclibUrl(t), 7000, text => {
            const res = JSON.parse(text);
            return res.syncedLyrics ? Providers.parseLrc(res.syncedLyrics) : null;
        });
        _get(req, "musixmatch", Providers.musixmatchUrl(t), 8000, text => {
            const res = JSON.parse(text);
            const meta = res.cachedMeta || res.metadata || res.track || res.data?.track || {};
            if (!_matchesTrack(meta.title || "", meta.artist || "", Number(meta.duration || 0)))
                return null;
            return Providers.parseMusixmatch(res);
        });
        if (videoId) {
            _get(req, "simpmusic", Providers.simpMusicUrl(videoId), 6000, text => {
                const res = JSON.parse(text);
                const duration = _trackDuration();
                const tracks = (res.data || []).filter(track => duration <= 0 || Math.abs((track.duration || 0) - duration) <= 10);
                tracks.sort((a, b) => Math.abs((a.duration || 0) - duration) - Math.abs((b.duration || 0) - duration));
                const track = tracks[0];
                if (!track)
                    return null;
                const rich = track.richSyncLyrics ? Providers.parseLrc(track.richSyncLyrics) : [];
                return rich.length ? rich : (track.syncedLyrics ? Providers.parseLrc(track.syncedLyrics) : null);
            });
        }
        if (root.appleToken) {
            Requests.get(Providers.appleSearchUrl(t), text => {
                if (req !== root.requestId)
                    return;
                let hit = null;
                try {
                    hit = Providers.bestAppleSong(JSON.parse(text), t);
                } catch (e) {
                    hit = null;
                }
                if (!hit) {
                    _settle(req, "paxsenix-apple", null, null);
                    return;
                }
                _get(req, "paxsenix-apple", Providers.paxsenixAppleUrl(hit.id), 6000, body => {
                    const res = JSON.parse(body);
                    return Providers.parseTtml(res.ttml || res.content || "");
                });
            }, () => _settle(req, "paxsenix-apple", null, null), {
                "Authorization": `Bearer ${root.appleToken}`,
                "Origin": "https://music.apple.com",
                "Referer": "https://music.apple.com/"
            }, 5000);
        }
    }

    // LyricsPlus runs on volunteer mirrors; walk them until one answers.
    function _fetchLyricsPlus(req: int, t: var, hostIndex: int): void {
        if (req !== root.requestId)
            return;
        if (hostIndex >= Providers.lyricsPlusHosts.length) {
            _settle(req, "lyricsplus", null, null);
            return;
        }
        Requests.get(Providers.lyricsPlusUrl(Providers.lyricsPlusHosts[hostIndex], t), text => {
            if (req !== root.requestId)
                return;
            let lines = null;
            try {
                lines = Providers.parseKpoe(JSON.parse(text));
            } catch (e) {
                lines = null;
            }
            if (lines && lines.length)
                _settle(req, "lyricsplus", lines, null);
            else
                _fetchLyricsPlus(req, t, hostIndex + 1);
        }, () => _fetchLyricsPlus(req, t, hostIndex + 1), {}, 4500);
    }

    // YouTube captions need a Python helper, so they only run when no
    // network provider produced word-synced lyrics.
    function _startYoutube(req: int): bool {
        const p = Players.active;
        const duration = _trackDuration();
        if (req !== root.requestId || !p || !_queryArtist() || duration > 900 || _isPlaceholderTitle(p.trackTitle))
            return false;
        if (youtubeProcess.running)
            youtubeProcess.running = false;
        root.youtubeStarted = true;
        root.youtubeEligible = true;
        root.loading = !root.selectedSourceId;
        if (!root.selectedSourceId)
            root.status = qsTr("Checking YouTube captions...");
        youtubeProcess.requestId = req;
        youtubeProcess.command = ["nice", "-n", "10", "python3", `${Quickshell.shellDir}/utils/scripts/youtube_lyrics.py`,
            "--title", _queryTitle(), "--artist", _queryArtist(), "--duration", String(duration)];
        youtubeProcess.running = true;
        youtubeTimeout.requestId = req;
        youtubeTimeout.restart();
        return true;
    }

    function _finishYoutube(req: int, output: string, errorOutput: string): void {
        if (req !== root.requestId)
            return;
        youtubeTimeout.stop();
        root.youtubeStarted = false;
        root.youtubeFinished = true;
        try {
            const result = JSON.parse(output || "{}");
            if (!result.success || !Providers.hasLineTiming(result.lyrics || []))
                throw new Error(result.error || errorOutput || "No usable YouTube captions");
            root.youtubeFailure = "";
            const language = result.language ? ` (${result.language})` : "";
            _addSource(Providers.parseLegacy(result.lyrics), "youtube", "YouTube captions", qsTr("YouTube captions%1").arg(language), {
                id: result.videoId || "captions",
                title: result.sourceTitle || _queryTitle(),
                language: result.language || ""
            });
        } catch (e) {
            root.youtubeFailure = String(e);
        }
        _reconsider(req, true);
        if (!root.selectedSourceId) {
            root.loading = Lyrics.loading;
            if (!Lyrics.loading)
                _setNativeFallback();
        }
    }

    // ---- model --------------------------------------------------------------

    function _loadLines(lines: var, source: string, message: string): void {
        if (!Providers.hasLineTiming(lines)) {
            root.hasSyllables = false;
            root.ownsTiming = false;
            root.loading = false;
            _setNativeFallback();
            return;
        }

        lyricsModel.clear();
        let timedSyllableCount = 0;
        const convert = syllables => (syllables || []).map(syl => {
            if (Number(syl.duration || 0) > 0)
                timedSyllableCount++;
            return {
                time: Number(syl.time || 0) / 1000,
                duration: Number(syl.duration || 0) / 1000,
                text: _cleanText(syl.text || "")
            };
        });
        for (const line of lines) {
            const bg = line.bg ? { text: _cleanText(line.bg.text || ""), syllabus: convert(line.bg.syllabus) } : null;
            _appendLine(_cleanText(line.text || ""), Number(line.time || 0) / 1000, Number(line.duration || 0) / 1000,
                convert(line.syllabus), line.agent, bg);
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
            formatVersion: 4,
            key: root.loadedKey,
            selectedSourceId: root.selectedSourceId,
            userSelected: root.userSelectedSource,
            sources
        });
        saveCache.command = ["sh", "-c", `mkdir -p ${_shellQuote(root.cacheDir)} && printf %s ${_shellQuote(payload)} > ${_shellQuote(root.cachePath)}.tmp && mv -f ${_shellQuote(root.cachePath)}.tmp ${_shellQuote(root.cachePath)}`];
        saveCache.running = true;
    }

    function indexForTime(time: real): int {
        if (!root.ownsTiming)
            return Lyrics.indexForTime(time);

        const target = time - Lyrics.offset + 0.1;
        // Binary search: called every frame by the immersive view.
        let lo = 0;
        let hi = lyricsModel.count - 1;
        let found = -1;
        while (lo <= hi) {
            const mid = (lo + hi) >> 1;
            if (lyricsModel.get(mid).time <= target) {
                found = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        return found;
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
        running: root.visibleConsumers && root.hasLyrics && !!Players.active
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

        // Leaves the cache read a moment to land before going online; a
        // trusted cached Apple result skips the network entirely.
        interval: 120
        repeat: false
        onTriggered: {
            if (requestId !== root.requestId)
                return;
            const selected = root.sourceRecords[root.selectedSourceId];
            if (root.cacheLoaded && selected && selected.wordSynced && selected.priority <= Providers.rankOf("lyricsplus")) {
                root.networkSettled = true;
                root.loading = false;
                return;
            }
            root._fetchOnline(requestId);
        }
    }

    Timer {
        id: graceTimer

        property int requestId: -1

        interval: 1400
        repeat: false
        onTriggered: root._reconsider(requestId, true)
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
            root._finishYoutube(requestId, "", "YouTube captions timed out");
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
                if ((cached.formatVersion === 3 || cached.formatVersion === 4) && Array.isArray(cached.sources)) {
                    for (const source of cached.sources) {
                        const providerId = source.providerId || String(source.provider || "cached").toLowerCase().replace(/[^a-z0-9]+/g, "");
                        const id = root._addSource(Providers.parseLegacy(source.lyrics || []), providerId,
                            source.provider || "Cached", source.detail || qsTr("Cached lyrics"), {
                                sourceId: source.id || "",
                                title: source.title,
                                artist: source.artist,
                                language: source.language || ""
                            });
                        if (!selectedId)
                            selectedId = id;
                    }
                    if (cached.selectedSourceId && root.sourceRecords[cached.selectedSourceId])
                        selectedId = cached.selectedSourceId;
                    root.userSelectedSource = !!cached.userSelected;
                }
                root.restoringSources = false;
                if (selectedId) {
                    root.cacheLoaded = true;
                    root._selectSource(selectedId, root.userSelectedSource);
                }
            } catch (e) {
                root.restoringSources = false;
                root.cacheLoaded = false;
            }
        }
    }

    // The Apple Music web token is maintained by caelestia-motion-art.
    FileView {
        path: `${Paths.cache}/motion-art/token.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const state = JSON.parse(text());
                root.appleToken = state.token && state.exp * 1000 > Date.now() ? state.token : "";
            } catch (e) {
                root.appleToken = "";
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

        interval: 400
        repeat: false
        onTriggered: root._writeSourcesCache()
    }

    Process {
        id: saveCache
    }

    Process {
        id: romanizer

        property string recordId: ""
        property int requestId: -1
        property string payload: ""

        command: ["nice", "-n", "5", "caelestia-romaji"]
        stdinEnabled: true
        stdout: StdioCollector {
            id: romanizerOutput
        }
        onStarted: {
            write(payload);
            stdinEnabled = false;
        }
        onExited: code => {
            stdinEnabled = true;
            if (requestId !== root.requestId)
                return;
            const record = root.sourceRecords[recordId];
            if (!record)
                return;
            try {
                const result = JSON.parse(romanizerOutput.text || "{}");
                record.romanized = Providers.parseLegacy(result.lines || []);
            } catch (e) {
                record.romanized = null;
            }
            if (!record.romanized || !record.romanized.length) {
                // Never leave the view empty: fall back to the original script.
                record.romanized = record.lyrics;
            }
            if (root.selectedSourceId === recordId)
                root._selectSource(recordId, root.userSelectedSource);
        }
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
        onExited: _code => root._finishYoutube(requestId, youtubeOutput.text, youtubeError.text) // qmllint disable signal-handler-parameters
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
            if (!root.selectedSourceId && root.networkSettled && !root.youtubeStarted)
                root.loading = Lyrics.loading;
        }
    }
}
